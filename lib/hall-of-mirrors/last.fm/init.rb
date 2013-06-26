#!/usr/bin/env ruby

require 'lastfm'
require 'pathname'

HERE = Pathname.new(__FILE__) + '..'

def authenticate
  key    = ENV['LASTFM_KEY']
  secret = ENV['LASTFM_SECRET']

  lastfm = Lastfm.new(key, secret)
  token  = lastfm.auth.get_token

  puts "Visit http://www.last.fm/api/auth/?api_key=#{key}&token=#{token} and grant me permissions! Press enter when done."
  done = gets

  session = lastfm.auth.get_session(:token => token)
  lastfm.session = session['key']

  File.write(HERE + '_auth', session['key'])
end

authenticate unless (HERE + '_auth').exist?
