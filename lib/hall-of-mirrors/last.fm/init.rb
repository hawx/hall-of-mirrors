#!/usr/bin/env ruby

require 'lastfm'

class Hall::Lastfm
  module Init
    extend self

    def authenticate
      key    = ENV['LASTFM_KEY']
      secret = ENV['LASTFM_SECRET']

      lastfm = Lastfm.new(key, secret)
      token  = lastfm.auth.get_token

      puts "Visit http://www.last.fm/api/auth/?api_key=#{key}&token=#{token} and grant me permissions! Press enter when done."
      done = $stdin.gets

      session = lastfm.auth.get_session(:token => token)
      lastfm.session = session['key']

      Config.set :lastfm, :session, session['key']
    end
  end

  command :init do
    if Config.has?(:lastfm, :session)
      puts "You are already authenticated."
      exit
    end

    Init.authenticate
  end
end
