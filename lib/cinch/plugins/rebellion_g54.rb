require 'cinch'
require 'cinch/plugins/game_bot'
require 'rebellion_g54/game'
require 'rebellion_g54/role'

module Cinch; module Plugins; class RebellionG54 < GameBot
  include Cinch::Plugin

  xmatch(/choices/i, method: :choices, group: :rebellion_g54)
  xmatch(/me/i, method: :whoami, group: :rebellion_g54)
  xmatch(/table(?:\s+(##?\w+))?/i, method: :table, group: :rebellion_g54)
  xmatch(/status/i, method: :status, group: :rebellion_g54)

  xmatch(/help(?: (.+))?/i, method: :help, group: :rebellion_g54)
  xmatch(/rules/i, method: :rules, group: :rebellion_g54)

  xmatch(/roles\s+list/i, method: :list_possible_roles, group: :rebellion_g54)
  xmatch(/roles(?:\s+(##?\w+))?$/i, method: :get_roles, group: :rebellion_g54)
  xmatch(/roles(?:\s+(##?\w+))?\s+random(?:\s+(.+))?/i, method: :random_roles, group: :rebellion_g54)
  xmatch(/roles(?:\s+(##?\w+))? (.+)$/i, method: :set_roles, group: :rebellion_g54)

  xmatch(/peek(?:\s+(##?\w+))?/i, method: :peek, group: :rebellion_g54)

  xmatch(/(\S+)(?:\s+(.*))?/, method: :rebellion_g54, group: :rebellion_g54)

  common_commands

  class ChannelOutputter
    def initialize(bot, game, c)
      @bot = bot
      @game = game
      @chan = c
    end

    def player_died(user)
      @bot.player_died(user, @chan)
    end

    def new_cards(user)
      @bot.tell_cards(@game, user: user)
    end

    def puts(msg)
      @chan.send(msg)
    end
  end

  #--------------------------------------------------------------------------------
  # Implementing classes should override these
  #--------------------------------------------------------------------------------

  def game_class
    ::RebellionG54::Game
  end

  def do_start_game(m, game, options)
    success, error = game.start_game
    unless success
      m.reply(error, true)
      return
    end

    Channel(game.channel_name).send("Welcome to game #{game.id}, with roles #{game.roles}")
    order = game.users.map { |u| dehighlight_nick(u.nick) }.join(' ')
    Channel(game.channel_name).send("Player order is #{order}")

    # Tell everyone of their initial stuff
    game.each_player.each { |player| tell_cards(game, player: player, game_start: true) }

    game.output_streams << ChannelOutputter.new(self, game, Channel(game.channel_name))
    announce_decision(game)
  end

  def do_reset_game(game)
    chan = Channel(game.channel_name)
    chan.send("Game #{game.id} Turn #{game.turn_number} - #{game.roles}")
    info = table_info(game, show_secrets: true)
    chan.send(info)
  end

  def do_replace_user(game, replaced_user, replacing_user)
    tell_cards(game, replacing_user) if game.started?
  end

  def bg3po_invite_command(channel_name)
    # Nah, I don't want to do bg3po
  end

  #--------------------------------------------------------------------------------
  # Other player management
  #--------------------------------------------------------------------------------

  def player_died(user, channel)
    # Can't use remove_user_from_game because remove would throw an exception.
    # Instead, just do the same thing it does...
    channel.devoice(user)
    # I'm astounded that I can access my parent's @variable
    @user_games.delete(user)
  end

  def tell_cards(game, user: nil, player: nil, game_start: false)
    player ||= game.find_player(user)
    user ||= player.user
    turn = game_start ? 'starting hand' : "Turn #{game.turn_number}"
    user.send("Game #{game.id} #{turn}: #{player_info(player, show_secrets: true)}")
  end

  #--------------------------------------------------------------------------------
  # Game
  #--------------------------------------------------------------------------------

  def announce_decision(game)
    desc = game.decision_description
    players = game.choice_names.keys
    choices = game.choice_names.values.flatten.uniq
    Channel(game.channel_name).send(
      "Game #{game.id} Turn #{game.turn_number} - #{desc} - Waiting on #{players.join(', ')} to pick between #{choices.join(', ')}"
    )
    players.each { |p|
      explanations = game.choice_explanations(p)
      User(p).send(explanations.map { |e| "[#{e}]" }.join(' '))
    }
  end

  def rebellion_g54(m, command, args = '')
    game = self.game_of(m)
    return unless game && game.started? && game.has_player?(m.user)

    success, error = game.take_choice(m.user, command, args || '')

    if success
      if game.winner
        chan = Channel(game.channel_name)
        chan.send("Congratulations! #{game.winner.name} is the winner!!!")
        info = table_info(game, show_secrets: true)
        chan.send(info)
        self.start_new_game(game)
      else
        announce_decision(game)
      end
    else
      m.user.send(error)
    end
  end

  def choices(m)
    game = self.game_of(m)
    return unless game && game.started? && game.has_player?(m.user)
    explanations = game.choice_explanations(m.user)
    m.user.send(explanations.map { |e| "[#{e}]" }.join(' '))
  end

  def whoami(m)
    game = self.game_of(m)
    return unless game && game.started? && game.has_player?(m.user)
    tell_cards(game, user: m.user)
  end

  def table(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see a game', '!table'])
    return unless game && game.started?

    m.reply("Game #{game.id} Turn #{game.turn_number} - #{game.roles}")
    info = table_info(game)
    m.reply(info)
  end

  def status(m)
    game = self.game_of(m)
    return unless game

    if !game.started?
      if game.size == 0
        m.reply('No game in progress. Join and start one!')
      else
        m.reply("A game is forming. #{game.size} players have joined: #{game.users.map(&:name).join(', ')}")
      end
      return
    end

    desc = game.decision_description
    players = game.choice_names.keys
    m.reply("Game #{game.id} Turn #{game.turn_number} - #{desc} - Waiting on #{players.join(', ')}")
  end

  def peek(m)
    return unless self.is_mod?(m.user)
    game = self.game_of(m, channel_name, ['peek', '!peek'])
    return unless game && game.started?

    if game.has_player?(m.user)
      m.user.send('Cheater!!!')
      return
    end

    m.user.send("Game #{game.id} Turn #{game.turn_number} - #{game.roles}")
    info = table_info(game, show_secrets: true)
    m.user.send(info)
  end

  #--------------------------------------------------------------------------------
  # Help for player/table info
  #--------------------------------------------------------------------------------

  def table_info(game, show_secrets: false)
    game.each_player.map { |player|
      "#{player.user.name}: #{player_info(player, show_secrets: show_secrets)}"
    }.concat(game.each_dead_player.map { |player|
      "#{player.user.name}: #{player_info(player, show_secrets: show_secrets)}"
    }).join("\n")
  end

  def player_info(player, show_secrets: false)
    cards = []
    cards.concat(player.each_live_card.map { |c|
      "(#{show_secrets ? ::RebellionG54::Role.to_s(c.role) : '########'})"
    })
    cards.concat(player.each_side_card.map { |c, r|
      "<#{show_secrets ? ::RebellionG54::Role.to_s(c.role) : "??#{::RebellionG54::Role.to_s(r)}??"}>"
    })
    cards.concat(player.each_revealed_card.map { |c|
      "[#{::RebellionG54::Role.to_s(c.role)}]"
    })
    "#{cards.join(' ')} - #{player.influence > 0 ? "Coins: #{player.coins}" : 'ELIMINATED'}"
  end

  #--------------------------------------------------------------------------------
  # Settings
  #--------------------------------------------------------------------------------

  def list_possible_roles(m)
    m.reply(::RebellionG54::Role::ALL.keys.map(&:to_s))
  end

  def get_roles(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see roles', '!roles'])
    return unless game

    m.reply("Game #{game.id} #{game.started? ? '' : "proposed #{game.roles.size} "}roles: #{game.roles}")
  end

  class Chooser
    attr_reader :roles
    def initialize
      @roles = []
      @advanced_only = false
      @basic_only = false
    end
    def advanced_only!
      @basic_only = false
      @advanced_only = true
    end
    def basic_only!
      @basic_only = true
      @advanced_only = false
    end
    def pick(desired_group)
      matching_chars = ::RebellionG54::Role::ALL.to_a.reject { |role, _| @roles.include?(role) }
      matching_chars.select! { |_, (group, _)| group == desired_group } if desired_group != :all
      matching_chars.select! { |_, (_, advanced)| advanced } if @advanced_only
      matching_chars.select! { |_, (_, advanced)| !advanced } if @basic_only
      @roles << matching_chars.map { |role, _| role }.sample unless matching_chars.empty?
      @advanced_only = false
      @basic_only = false
    end
  end

  def random_roles(m, channel_name = nil, spec = '')
    game = self.game_of(m, channel_name, ['change roles', '!roles'])
    return unless game && !game.started?

    if !spec || spec.strip.empty?
      m.reply('C = communications, $ = finance, F = force, S = special interests, A = all. Prepend + for only advanced, - for only basic.')
      m.reply('Perhaps -C-$-F-S-S or C$FSS or +C+$+F+S+S are good choices, but the sky is the limit...')
      return
    end

    chooser = Chooser.new
    spec.each_char { |c|
      case c.downcase
      when '-'; chooser.advanced_only!
      when '+'; chooser.basic_only!
      when 'c'; chooser.pick(:communications)
      when '$'; chooser.pick(:finance)
      when 'f'; chooser.pick(:force)
      when 's'; chooser.pick(:special_interests)
      when 'a'; chooser.pick(:all)
      end
    }

    game.roles = chooser.roles
    m.reply("Game #{game.id} now has #{game.roles.size} roles: #{game.roles}")
  end

  def set_roles(m, channel_name = nil, spec = '')
    game = self.game_of(m, channel_name, ['change roles', '!roles'])
    return unless game && !game.started?
    return if !spec || spec.strip.empty?

    roles = game.roles
    unknown = []
    spec.split.each { |s|
      if s[0] == '+'
        rest = s[1..-1].downcase
        matching_role = ::RebellionG54::Role::ALL.keys.find { |role| role.to_s == rest }
        if matching_role
          roles << matching_role
        else
          unknown << rest
        end
      elsif s[0] == '-'
        rest = s[1..-1].downcase
        roles.reject! { |role| role.to_s == rest }
      end
    }

    m.reply("These roles are unknown: #{unknown}") unless unknown.empty?
    game.roles = roles.uniq
    m.reply("Game #{game.id} now has #{game.roles.size} roles: #{game.roles}")
  end

  #--------------------------------------------------------------------------------
  # General
  #--------------------------------------------------------------------------------

  def help(m, page = '')
    page ||= ''
    case page.strip.downcase
    when '2'
      m.reply('Roles: roles (view current), roles list (list all supported), roles random, roles +add -remove')
      m.reply("Game commands: table (everyone's cards and coins), status (whose turn is it?)")
      m.reply('Game commands: me (your characters), choices (your current choices)')
    when '3'
      m.reply('Getting people to play: invite, subscribe, unsubscribe')
      m.reply('To get PRIVMSG: notice off. To get NOTICE: notice on')
    else
      m.reply("General help: All commands can be issued by '!command' or '#{m.bot.nick}: command' or PMing 'command'")
      m.reply('General commands: join, leave, start, who')
      m.reply('Game-related commands: help 2. Preferences: help 3')
    end
  end

  def rules(m)
    m.reply('https://www.boardgamegeek.com/thread/1369434 and https://boardgamegeek.com/filepage/107678')
  end
end; end; end
