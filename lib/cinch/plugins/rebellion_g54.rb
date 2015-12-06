require 'cinch'
require 'cinch/plugins/game_bot'
require 'rebellion_g54/game'
require 'rebellion_g54/role'

module Cinch; module Plugins; class RebellionG54 < GameBot
  include Cinch::Plugin

  match(/choices/i, method: :choices, group: :rebellion_g54)
  match(/me\s*$/i, method: :whoami, group: :rebellion_g54)
  match(/whoami/i, method: :whoami, group: :rebellion_g54)
  match(/table(?:\s+(##?\w+))?/i, method: :table, group: :rebellion_g54)

  match(/help(?: (.+))?/i, method: :help, group: :rebellion_g54)
  match(/rules/i, method: :rules, group: :rebellion_g54)

  match(/settings(?:\s+(##?\w+))?$/i, method: :get_settings, group: :rebellion_g54)
  match(/settings(?:\s+(##?\w+))? (.+)$/i, method: :set_settings, group: :rebellion_g54)

  match(/roles\s+list/i, method: :list_possible_roles, group: :rebellion_g54)
  match(/roles(?:\s+(##?\w+))?$/i, method: :get_roles, group: :rebellion_g54)
  match(/roles(?:\s+(##?\w+))?\s+random(?:\s+(.+))?/i, method: :random_roles, group: :rebellion_g54)
  match(/roles(?:\s+(##?\w+))? (.+)$/i, method: :set_roles, group: :rebellion_g54)

  match(/peek(?:\s+(##?\w+))?/i, method: :peek, group: :rebellion_g54)

  match(/(\S+)(?:\s+(.*))?/, method: :rebellion_g54, group: :rebellion_g54)

  add_common_commands

  IGNORED_COMMANDS = COMMON_COMMANDS.dup.delete('join').freeze
  DEFAULT_ROLES = %i(banker director guerrilla peacekeeper politician).freeze

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

  def do_start_game(m, channel_name, players, settings, start_args)
    begin
      opts = {}
      opts[:synchronous_challenges] = settings[:synchronous_challenges] if settings.has_key?(:synchronous_challenges)
      roles = settings[:roles] || DEFAULT_ROLES
      game = ::RebellionG54::Game.new(channel_name, players.map(&:user), roles, **opts)
    rescue => e
      m.reply("Failed to start game because #{e}", true)
      return
    end

    Channel(game.channel_name).send("Welcome to game #{game.id}, with roles #{game.roles}")
    order = game.users.map { |u| dehighlight_nick(u.nick) }.join(' ')
    Channel(game.channel_name).send("Player order is #{order}")

    # Tell everyone of their initial stuff
    game.each_player.each { |player| tell_cards(game, player: player, game_start: true) }

    game.output_streams << ChannelOutputter.new(self, game, Channel(game.channel_name))
    announce_decision(game)
    game
  end

  def do_reset_game(game)
    chan = Channel(game.channel_name)
    info = table_info(game, show_secrets: true)
    chan.send(info)
  end

  def do_replace_user(game, replaced_user, replacing_user)
    tell_cards(game, replacing_user)
  end

  def game_status(game)
    decision_info(game)
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
    Channel(game.channel_name).send(decision_info(game, show_choices: true))
    game.choice_names.keys.each { |p|
      explanations = game.choice_explanations(p)
      send_choice_explanations(explanations, p)
    }
  end

  def rebellion_g54(m, command, args = '')
    # Don't invoke rebellion_g54 catchall for !who, for example.
    return if IGNORED_COMMANDS.include?(command.downcase)

    game = self.game_of(m)
    return unless game && game.users.include?(m.user)

    args = args ? args.split : []
    success, error = game.take_choice(m.user, command, *args)

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
    return unless game && game.users.include?(m.user)
    explanations = game.choice_explanations(m.user)
    if explanations.empty?
      m.user.send("You don't need to make any choices right now.")
    else
      send_choice_explanations(explanations, m.user, show_unavailable: true)
    end
  end

  def whoami(m)
    game = self.game_of(m)
    return unless game && game.users.include?(m.user)
    tell_cards(game, user: m.user)
  end

  def table(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see a game', '!table'])
    return unless game

    info = table_info(game)
    m.reply(info)
  end

  def peek(m, channel_name = nil)
    return unless self.is_mod?(m.user)
    game = self.game_of(m, channel_name, ['peek', '!peek'])
    return unless game

    if game.users.include?(m.user)
      m.user.send('Cheater!!!')
      return
    end

    info = table_info(game, show_secrets: true)
    m.user.send(info)
  end

  #--------------------------------------------------------------------------------
  # Help for player/table info
  #--------------------------------------------------------------------------------

  def send_choice_explanations(explanations, user, show_unavailable: false)
    available, unavailable = explanations.to_a.partition { |_, info| info[:available] }
    user.send(available.map { |label, info| "[#{label}: #{info[:description]}]" }.join(' '))

    return unless show_unavailable && !unavailable.empty?

    user.send('Unavailable: ' + unavailable.map { |label, info|
      "[#{label}: #{info[:description]} - #{info[:why_unavailable]}]"
    }.join(' '))
  end

  def decision_info(game, show_choices: false)
    desc = game.decision_description
    players = game.choice_names.keys
    choices = show_choices ? " to pick between #{game.choice_names.values.flatten.uniq.join(', ')}" : ''
    "Game #{game.id} Turn #{game.turn_number} - #{desc} - Waiting on #{players.join(', ')}#{choices}"
  end

  def table_info(game, show_secrets: false)
    role_tokens = game.role_tokens
    roles = game.roles.map { |r|
      tokens = role_tokens[r] || []
      tokens_str = (tokens.empty? ? '' : " (#{tokens.map { |t| t.to_s.capitalize }.join(', ')})")
      "#{::RebellionG54::Role.to_s(r)}#{tokens_str}"
    }.join(', ')
    player_tokens = game.player_tokens
    "Game #{game.id} Turn #{game.turn_number} - #{roles}\n" + game.each_player.map { |player|
      "#{player.user.name}: #{player_info(player, show_secrets: show_secrets, tokens: player_tokens[player.user])}"
    }.concat(game.each_dead_player.map { |player|
      "#{player.user.name}: #{player_info(player, show_secrets: show_secrets)}"
    }).join("\n")
  end

  def player_info(player, show_secrets: false, tokens: [])
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
    token_str = tokens.empty? ? '' : " - #{tokens.map { |t| t.to_s.capitalize }.join(', ')}"
    "#{cards.join(' ')} - #{player.influence > 0 ? "Coins: #{player.coins}" : 'ELIMINATED'}#{token_str}"
  end

  #--------------------------------------------------------------------------------
  # Settings
  #--------------------------------------------------------------------------------

  def list_possible_roles(m)
    m.reply(::RebellionG54::Role::ALL.keys.map(&:to_s))
  end

  def get_settings(m, channel_name = nil)
    if (game = self.game_of(m, channel_name))
      m.reply("Game #{game.id} - Synchronous challenges: #{game.synchronous_challenges}")
      return
    end

    waiting_room = self.waiting_room_of(m, channel_name, ['see settings', '!settings'])
    m.reply("Next game will have synchronous challenges: #{waiting_room.settings[:synchronous_challenges]}")
  end

  def set_settings(m, channel_name = nil, spec = '')
    waiting_room = self.waiting_room_of(m, channel_name, ['change settings', '!settings'])
    game = self.game_of(m, channel_name)

    unknown = []
    spec.split.each { |s|
      if s[0] == '+'
        desire = true
      elsif s[0] == '-'
        desire = false
      else
        unknown << s
      end
      case s[1..-1]
      when 'sync'
        game.synchronous_challenges = desire if game
        waiting_room.settings[:synchronous_challenges] = desire
      else
        unknown << s[1..-1]
      end
    }

    m.reply("These settings are unknown: #{unknown}") unless unknown.empty?
    if game
      m.reply("Game #{game.id} - Synchronous challenges: #{game.synchronous_challenges}")
    elsif
      m.reply("Next game will have synchronous challenges: #{waiting_room.settings[:synchronous_challenges]}")
    end
  end

  def get_roles(m, channel_name = nil)
    if (game = self.game_of(m, channel_name))
      m.reply("Game #{game.id} roles: #{game.roles}")
      return
    end

    waiting_room = self.waiting_room_of(m, channel_name, ['see roles', '!roles'])
    roles = waiting_room.settings[:roles] || DEFAULT_ROLES
    m.reply("Next game proposed #{roles.size} roles: #{roles}")
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
    waiting_room = self.waiting_room_of(m, channel_name, ['change roles', '!roles'])

    if !spec || spec.strip.empty?
      m.reply('C = communications, $ = finance, F = force, S = special interests, A = all. Prepend + for only advanced, - for only basic.')
      m.reply('Perhaps -C-$-F-S-S or C$FSS or +C+$+F+S+S are good choices, but the sky is the limit...')
      return
    end

    chooser = Chooser.new
    spec.each_char { |c|
      case c.downcase
      when '+'; chooser.advanced_only!
      when '-'; chooser.basic_only!
      when 'c'; chooser.pick(:communications)
      when '$'; chooser.pick(:finance)
      when 'f'; chooser.pick(:force)
      when 's'; chooser.pick(:special_interests)
      when 'a'; chooser.pick(:all)
      end
    }

    waiting_room.settings[:roles] = chooser.roles
    m.reply("Next game will have #{chooser.roles.size} roles: #{chooser.roles}")
  end

  def set_roles(m, channel_name = nil, spec = '')
    waiting_room = self.waiting_room_of(m, channel_name, ['change roles', '!roles'])
    return if !spec || spec.strip.empty?

    roles = waiting_room.settings[:roles] || DEFAULT_ROLES.dup
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
    roles.uniq!
    waiting_room.settings[:roles] = roles
    m.reply("Next game will have #{roles.size} roles: #{roles}")
  end

  #--------------------------------------------------------------------------------
  # General
  #--------------------------------------------------------------------------------

  def help(m, page = '')
    page ||= ''
    page = '' if page.strip.downcase == 'mod' && !self.is_mod?(m.user)
    case page.strip.downcase
    when 'mod'
      m.reply('Cheating: peek')
      m.reply('Game admin: kick, reset, replace')
    when '2'
      m.reply('Roles: roles (view current), roles list (list all supported), roles random, roles +add -remove')
      m.reply("Game commands: table (everyone's cards and coins), status (whose turn is it?)")
      m.reply('Game commands: me (your characters), choices (your current choices)')
    when '3'
      m.reply('One challenger at a time: settings +sync. Everyone challenges at once: settings -sync')
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
