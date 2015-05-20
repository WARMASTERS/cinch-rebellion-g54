require 'simplecov'
SimpleCov.start { add_filter '/spec/' }

require 'cinch/test'
require 'cinch/plugins/rebellion_g54'

def get_replies_text(m)
  get_replies(m).map(&:text)
end

class MessageReceiver
  attr_accessor :messages

  def initialize
    @messages = []
  end

  def devoice(_)
  end
  def moderated=(_)
  end

  def send(m)
    @messages << m
  end
end

RSpec.describe Cinch::Plugins::RebellionG54 do
  include Cinch::Test

  let(:chan) { MessageReceiver.new }
  let(:channel1) { '#test' }
  let(:player1) { 'test1' }
  let(:player2) { 'test2' }
  let(:user1) { MessageReceiver.new }
  let(:user2) { MessageReceiver.new }
  let(:players) { {
    player1 => user1,
    player2 => user2,
  }}

  let(:opts) {{
    :channels => [channel1],
    :settings => '/dev/null',
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

  def msg(text, nick: player1)
    make_message(bot, text, nick: nick, channel: channel1)
  end

  # Doh this sucks.
  # It's because when joining a game, bot checks that you're in that channel
  # I can't even stub out :Channel because it's on the parent, apparently?
  # So I'll just have to do whatever game_bot does.
  def force_join(message)
    games = plugin.instance_variable_get(:@games)
    game = games[message.channel]
    game.add_player(message.user)
    user_games = plugin.instance_variable_get(:@user_games)
    user_games[message.user] = game
  end

  it 'makes a test bot' do
    expect(bot).to be_a(Cinch::Bot)
  end

  context 'in a game' do
    before :each do
      force_join(msg('!join'))
      force_join(msg('!join', nick: player2))
      allow(plugin).to receive(:Channel).with(channel1).and_return(chan)
      games = plugin.instance_variable_get(:@games)
      game = games[channel1]
      game.each_player.each { |p| allow(p.user).to receive(:send) { |x| players[p.user.name].messages << x } }
      get_replies(msg('!start'))
    end

    it 'says hi' do
      puts "HI"
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
