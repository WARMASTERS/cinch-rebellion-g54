# cinch-rebellion-g54

This is an IRC bot using [cinch](https://github.com/cinchrb/cinch), [cinch-game-bot](https://github.com/petertseng/cinch-game-bot), and [rebellion_g54](https://github.com/petertseng/rebellion_g54) to allow play-by-IRC of "Coup: Guatemala 1954" or "Coup: Rebellion G54" by Rikki Tahta:

https://boardgamegeek.com/boardgame/148943


[![Build Status](https://travis-ci.org/petertseng/cinch-rebellion_g54.svg?branch=master)](https://travis-ci.org/petertseng/cinch-rebellion_g54)

## Setup

You'll need a recent version of [Ruby](https://www.ruby-lang.org/).
Ruby 2.1 or newer is required because of required keyword arguments.
The [build status](https://travis-ci.org/petertseng/cinch-rebellion_g54) will confirm compatibility with various Ruby versions.
Note that [2.1 is in security maintenance mode](https://www.ruby-lang.org/en/news/2016/02/24/support-plan-of-ruby-2-0-0-and-2-1/), so it would be better to use a later version.

You'll need to install the required gems, which can be done automatically via `bundle install`, or manually by reading the `Gemfile` and using `gem install` on each gem listed.

## Usage

Given that you have performed the requisite setup, the minimal code to get a working bot might resemble:

```ruby
require 'cinch'
require 'cinch/plugins/rebellion_g54'

bot = Cinch::Bot.new do
  configure do |c|
    c.nick            = 'RebellionG54Bot'
    c.server          = 'irc.example.org'
    c.channels        = ['#playrebelliong54']
    c.plugins.plugins = [Cinch::Plugins::RebellionG54]
    c.plugins.options[Cinch::Plugins::RebellionG54] = {
      channels: ['#playrebelliong54'],
      settings: 'rebelliong54-settings.yaml',
    }
  end
end

bot.start
```
