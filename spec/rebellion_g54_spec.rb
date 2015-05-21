require 'simplecov'
SimpleCov.start { add_filter '/spec/' }

require 'cinch/test'
require 'cinch/plugins/rebellion_g54'

def get_replies_text(m)
  replies = get_replies(m)
  # If you wanted, you could read all the messages as they come, but that might be a bit much.
  # You'd want to check the messages of user1, user2, and chan as well.
  # replies.each { |x| puts(x.text) }
  replies.map(&:text)
end

class MessageReceiver
  attr_reader :name
  attr_accessor :messages

  def initialize(name)
    @name = name
    @messages = []
  end

  def send(m)
    @messages << m
  end
end

class TestChannel < MessageReceiver
  def voiced
    []
  end
  def devoice(_)
  end
  def moderated=(_)
  end
end

RSpec.describe Cinch::Plugins::RebellionG54 do
  include Cinch::Test

  let(:channel1) { '#test' }
  let(:chan) { TestChannel.new(channel1) }
  let(:player1) { 'test1' }
  let(:player2) { 'test2' }
  let(:npmod) { 'npmod' }
  let(:user1) { MessageReceiver.new(player1) }
  let(:user2) { MessageReceiver.new(player2) }
  let(:players) { {
    player1 => user1,
    player2 => user2,
  }}

  let(:opts) {{
    :channels => [channel1],
    :settings => '/dev/null',
    :mods => [npmod, player1],
    :allowed_idle => 300,
  }}
  let(:bot) {
    b = make_bot(described_class, opts) { |c|
      self.loggers.first.level = :warn
    }
    # No, c.nick = 'testbot' doesn't work because... isupport?
    allow(b).to receive(:nick).and_return('testbot')
    b
  }
  let(:plugin) { bot.plugins.first }

  def msg(text, nick: player1, channel: channel1)
    make_message(bot, text, nick: nick, channel: channel)
  end
  def authed_msg(text, nick: player1, channel: channel1)
    m = msg(text, nick: nick, channel: channel)
    allow(m.user).to receive(:authed?).and_return(true)
    allow(m.user).to receive(:authname).and_return(nick)
    m
  end

  def join(message)
    expect(message.channel).to receive(:has_user?).with(message.user).and_return(true)
    expect(message.channel).to receive(:voice).with(message.user)
    get_replies(message)
  end

  it 'makes a test bot' do
    expect(bot).to be_a(Cinch::Bot)
  end

  it 'does not start a game with bogus roles' do
    join(msg('!join'))
    join(msg('!join', nick: player2))
    get_replies(msg('!roles -banker'))
    expect(get_replies_text(msg('!start'))).to be == [
      "#{player1}: Need 5 roles instead of 4"
    ]
  end

  context 'in a game' do
    before :each do
      join(msg('!join'))
      join(msg('!join', nick: player2))
      allow(plugin).to receive(:Channel).with(channel1).and_return(chan)
      get_replies(msg('!start'))
    end

    # This is fragile but I can't do much better?
    let(:player_order) {
      get_replies_text(msg('!who')).map { |text|
        text.gsub(8203.chr('UTF-8'), '')
      }.find { |text|
        # Doing this to filter out the "not a valid choice" that we might get.
        text.include?(player1) && text.include?(player2)
      }.split
    }
    # Here, p1 and p2 mean original player order, not related to player1/player2
    let(:p1) { player_order.first }
    let(:p2) { player_order.last }

    it 'has a sane player order' do
      expect([p1, p2]).to match_array([player1, player2])
    end

    context 'playing the game' do
      before(:each) do
        3.times do
          get_replies(msg('!banker', nick: p1))
          get_replies(msg('!pass', nick: p2))
          get_replies(msg('!income', nick: p2))
        end
        get_replies(msg("!coup #{p2}", nick: p1))
        get_replies(msg("!lose1", nick: p2))
        # p1 at 4 coins, p2 at 5 coins
        get_replies(msg("!income", nick: p2))
        get_replies(msg('!banker', nick: p1))
        get_replies(msg('!pass', nick: p2))
        get_replies(msg('!income', nick: p2))
        # p1 can win by using coup next turn
      end

      it 'can end the game' do
        chan.messages.clear
        # We don't get replies to this; they're just sent to the channel
        get_replies(msg("!coup #{p2}", nick: p1))
        expect(chan.messages).to be_any { |x| x.include?('winner') }
      end

      context 'after game has ended' do
        before(:each) { get_replies(msg("!coup #{p2}", nick: p1)) }

        # OKAY, fine, these aren't actually joining the game,
        # but it checks the important part that I want to check:
        # the bot doesn't think the users are still in a game
        # If the bot did think that, it would reject with a different message

        it 'lets the winner join the next game' do
          replies = get_replies_text(msg('!join', nick: p1))
          expect(replies.first).to be =~ /need to be in .* to join/
        end

        it 'lets the loser join the next game' do
          replies = get_replies_text(msg('!join', nick: p2))
          expect(replies.first).to be =~ /need to be in .* to join/
        end
      end
    end

    describe 'choices' do
      it 'shows choices for p1' do
        choices = get_replies_text(msg('!choices', nick: p1))
        expect(choices).to_not be_empty
        expect(choices.first).to_not include("don't need to make")
      end

      it 'shows no choices for p2' do
        expect(get_replies_text(msg('!choices', nick: p2))).to be == [
          "You don't need to make any choices right now."
        ]
      end
    end

    describe 'whoami' do
      it 'tells p1 characters' do
        expect(get_replies_text(msg('!me'))).to_not be_empty
      end
    end

    describe 'table' do
      it 'shows the table' do
        expect(get_replies_text(msg('!table'))).to_not be_empty
      end
    end

    describe 'status' do
      it 'shows the status' do
        expect(get_replies_text(msg('!status'))).to_not be_empty
      end
    end

    describe 'get_roles' do
      it '!roles shows roles' do
        replies = get_replies_text(msg('!roles'))
        expect(replies).to_not be_empty
        expect(replies.first).to be =~ /Game.*roles/
      end
    end

    describe 'reset' do
      it 'lets a mod reset' do
        chan.messages.clear
        get_replies_text(authed_msg('!reset', nick: player1))
        expect(chan.messages).to be_any { |x| x.include?('reset') }
      end

      it 'does not respond to a non-mod' do
        chan.messages.clear
        get_replies_text(authed_msg('!reset', nick: player2))
        expect(chan.messages).to be_empty
      end
    end

    describe 'peek' do
      it 'calls a playing mod a cheater' do
        expect(get_replies_text(authed_msg('!peek', nick: player1))).to be == ['Cheater!!!']
      end

      it 'does not respond to a non-mod' do
        expect(get_replies_text(authed_msg('!peek', nick: player2))).to be_empty
      end

      it 'shows info to a non-playing mod' do
        replies = get_replies_text(authed_msg("!peek #{channel1}", nick: npmod))
        expect(replies).to_not be_empty
        expect(replies).to_not be_any { |x| x =~ /cheater/i }
      end
    end
  end

  describe 'get_settings' do
    it '!settings shows settings' do
      replies = get_replies_text(msg('!settings'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('Synchronous challenges')
    end
  end

  describe 'set_settings' do
    it '!settings +sync sets sync on' do
      replies = get_replies_text(msg('!settings +sync'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('Synchronous challenges: true')
    end

    it '!settings -sync sets sync off' do
      replies = get_replies_text(msg('!settings -sync'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('Synchronous challenges: false')
    end

    it '!settings +cheese complains about unknown' do
      replies = get_replies_text(msg('!settings +cheese'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('unknown')
    end

    it '!settings bogus complains about unknown' do
      replies = get_replies_text(msg('!settings bogus'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('unknown')
    end
  end

  describe 'get_roles' do
    it '!roles shows roles' do
      replies = get_replies_text(msg('!roles'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('5 roles')
    end
  end

  describe 'random_roles' do
    it '!roles random shows the random help' do
      replies = get_replies_text(msg('!roles random'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('communications')
    end

    it '!roles random C does something' do
      replies = get_replies_text(msg('!roles random C'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random $ does something' do
      replies = get_replies_text(msg('!roles random $'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random F does something' do
      replies = get_replies_text(msg('!roles random F'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random S does something' do
      replies = get_replies_text(msg('!roles random S'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random A does something' do
      replies = get_replies_text(msg('!roles random A'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random +A does something' do
      replies = get_replies_text(msg('!roles random +A'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end

    it '!roles random -A does something' do
      replies = get_replies_text(msg('!roles random -A'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('1 roles')
    end
  end

  describe 'list_roles' do
    it '!roles list lists roles' do
      replies = get_replies_text(msg('!roles list'))
      expect(replies).to_not be_empty
    end
  end

  describe 'set_roles' do
    it '!roles +lawyer adds the role' do
      replies = get_replies_text(msg('!roles +lawyer'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('6 roles')
    end

    it '!roles +banker does not add the duplicate role' do
      replies = get_replies_text(msg('!roles +banker'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('5 roles')
    end

    it '!roles +nonsense complains about nonsejse' do
      replies = get_replies_text(msg('!roles +nonsense'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('unknown')
    end

    it '!roles -banker removes the role' do
      replies = get_replies_text(msg('!roles -banker'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('4 roles')
    end

    it '!roles -nonsense removes no role' do
      replies = get_replies_text(msg('!roles -nonsejse'))
      expect(replies).to_not be_empty
      expect(replies.first).to include('5 roles')
    end
  end

  describe 'status' do
    it 'responds with no players' do
      replies = get_replies_text(msg('!status', channel: channel1))
      expect(replies).to be_all { |x| x =~ /no game/i }
      expect(replies.drop(1)).to be_empty
    end

    it 'responds with one player' do
      join(msg('!join'))
      replies = get_replies_text(msg('!status', channel: channel1))
      expect(replies).to be_all { |x| x =~ /1 player/i }
      expect(replies.drop(1)).to be_empty
    end
  end

  describe 'help' do
    let(:help_replies) {
      get_replies_text(make_message(bot, '!help', nick: player1))
    }

    it 'responds to !help' do
      expect(help_replies).to_not be_empty
    end

    it 'responds differently to !help 2' do
      replies2 = get_replies_text(make_message(bot, '!help 2', nick: player1))
      expect(replies2).to_not be_empty
      expect(help_replies).to_not be == replies2
    end

    it 'responds differently to !help 3' do
      replies3 = get_replies_text(make_message(bot, '!help 3', nick: player1))
      expect(replies3).to_not be_empty
      expect(help_replies).to_not be == replies3
    end
  end

  describe 'rules' do
    it 'responds to !rules' do
      expect(get_replies_text(make_message(bot, '!rules', nick: player1))).to_not be_empty
    end
  end
end
