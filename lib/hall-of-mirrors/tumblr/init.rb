#!/usr/bin/env ruby

require 'weary/request'
require 'weary/middleware'
require 'sinatra/base'
require 'launchy'
require_relative '../_common/global'


# This is largely stolen/modified from https://github.com/mwunsch/tumblr.
class AuthSite < Sinatra::Base
  HOST = 'http://www.tumblr.com/oauth'

  enable :inline_templates
  enable :sessions
  set :credential_path, nil

  def request_token(key, secret, callback)
    Weary::Request.new "#{HOST}/request_token", :POST do |req|
      req.params :oauth_callback => callback
      req.use Weary::Middleware::OAuth, :consumer_key => key,
              :consumer_secret => secret
    end
  end

  def access_token(token, token_secret, verifier, consumer_key, consumer_secret)
    Weary::Request.new "#{HOST}/access_token", :POST do |req|
      req.use Weary::Middleware::OAuth, :token => token,
              :token_secret => token_secret,
              :verifier => verifier,
              :consumer_key => ENV['TUMBLR_CONSUMER_KEY'],
              :consumer_secret => ENV['TUMBLR_CONSUMER_SECRET']
    end
  end

  get "/" do
    session[:consumer_key] = ENV['TUMBLR_CONSUMER_KEY']
    session[:consumer_secret] = ENV['TUMBLR_CONSUMER_SECRET']
    response = request_token(session[:consumer_key], session[:consumer_secret], url("/auth")).perform
    if response.success?
      result = Rack::Utils.parse_query(response.body)
      logger.info(request.host)
      session[:request_token_secret] = result["oauth_token_secret"]
      redirect to("#{HOST}/authorize?oauth_token=#{result['oauth_token']}")
    else
      status response.status
      erb response.body
    end
  end

  get "/auth" do
    halt 401, erb(:error) if params.empty?
    token = params["oauth_token"]
    verifier = params["oauth_verifier"]
    response = access_token(token, session[:request_token_secret], verifier,
                      session[:consumer_key], session[:consumer_secret]).perform
    if response.success?
      result = Rack::Utils.parse_query(response.body)
      Config.set :tumblr, :oauth_token, result['oauth_token']
      Config.set :tumblr, :oauth_token_secret, result['oauth_token_secret']

      status response.status
      erb :success
    else
      status response.status
      erb response.body
    end
  end
end


def authorize(*soak)
  sinatra_options = {
    :port => '4567',
    :bind => 'localhost',
    :credential_path => (ROOT + 'tumblr' + '_auth').to_s
  }
  AuthSite.run!(sinatra_options) do |server|
    ::Launchy.open("http://localhost:4567/")
  end
end


if Config.has?(:tumblr)
  puts "Already authorised."
  exit
end

authorize


__END__

@@ error

<p>
  It would appear the user denied access, or there was an error.
  </p>
<p>
  You can try to <a href="/">authenticate again</a> or return to the terminal in defeat and <span class="command">`Ctrl-C`</span>.
</p>


@@ form

<form class="auth" action="/">
          <label class="key">Consumer Key: <input name="key" /></label>
  <label class="secret">Consumer Secret: <input name="secret" /></label>
  <input type="submit" />
                     </form>
<p>
  You need to <a href="http://www.tumblr.com/oauth/apps" target="_blank">register for an application on Tumblr</a>, then put your <em>consumer</em> key and secret here.
</p>
<p>
  You will then be redirected to Tumblr to authenticate and authorize.
</p>


@@ layout

<!DOCTYPE html>
<html>
<head>
  <title>Authenticate and Authorize</title>
</head>
<body>
  <div class="main">
    <%= yield %>
  </div>
  </body>
</html>


@@ success

<p>
  Success! Your credentials were saved.
</p>
<p>
  Now return to your terminal and shut down this application by typing <span class="command">Ctrl-C</span> (<em>SIGINT</em>).
</p>
