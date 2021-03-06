require 'flickraw'

class Hall::Flickr
  module Init
    extend self

    # Runs the standard authenticartion flow. This involves printing a url and
    # waiting for the number given by it. When we have the tokens, we save them to
    # a local file so that they can be read, which saves having to authenticate
    # properly every time. Though it probably is not great for security...
    def run_authentication_flow
      token = flickr.get_request_token
      auth_url = flickr.get_authorize_url(token['oauth_token'])

      puts "Open this url in your process to complete the authication process: #{auth_url}"
      puts "Copy here the number given when you complete the process."
      verify = gets.strip

      begin
        flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)

        Config.set :flickr, :access_token, flickr.access_token
        Config.set :flickr, :access_secret, flickr.access_secret

      rescue FlickRaw::FailedResponse => e
        puts "Authentication failed : #{e.msg}"
        exit
      end
    end

    # If we've already been authenticated, use those details, otherwise get some
    # new ones.
    def authenticate
      flickr.access_token = Config.get(:flickr, :access_token)
      flickr.access_secret = Config.get(:flickr, :access_secret)

      run_authentication_flow unless login
    end

    def test_login
      if login
        puts "You are authenticated as #{login.username}"
      else
        puts "You are not authenticated"
      end
    end

    def login
      @login ||= flickr.test.login
    rescue FlickRaw::OAuthClient::FailedResponse
      false
    end
  end

  command :init do
    FlickRaw.api_key = ENV['FLICKR_KEY']
    FlickRaw.shared_secret = ENV['FLICKR_SECRET']

    Init.authenticate
    Init.test_login
  end
end
