#!/usr/bin/env ruby

require 'launchy'
require 'koala'
require 'pathname'
require 'sinatra/base'

module Hall::Facebook::Init
  OAUTH = Koala::Facebook::OAuth.new(ENV['FACEBOOK_APP_ID'],
                                 ENV['FACEBOOK_APP_SECRET'],
                                 'http://localhost:8080/auth')

  class AuthClient < Sinatra::Base
    get '/' do
      session[:app_id] = ENV['FACEBOOK_APP_ID']
      session[:app_secret] = ENV['FACEBOOK_APP_SECRET']

      redirect OAUTH.url_for_oauth_code(:permissions => [
                                          'user_photos',
                                          'friends_photos'])
    end

    get '/auth' do
      code = params['code']
      token = OAUTH.get_access_token(code)

      Config.set :facebook, :token, token
      "Wrote token, you can now quit!"
    end
  end
end

class Hall::Facebook
  command :init do
    action do
      if Config.has?(:facebook)
        puts "Already authorised."
        exit
      end

      sinatra_opts = {
        :port => '8080',
        :bind => 'localhost'
      }

      AuthClient.run!(sinatra_opts) do |server|
        ::Launchy.open("http://#{sinatra_opts[:bind]}:#{sinatra_opts[:port]}/")
      end
    end
  end
end
