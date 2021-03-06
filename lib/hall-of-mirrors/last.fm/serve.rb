#!/usr/bin/env ruby

# Misc. notes:
#
# Turns out the things I want to do with datamapper are a pain to acheive,
# viz. using multiple databases. Though it is understandable given it is not one
# of the main aims of the (or any other db) project. So a lot of this is
# handwaving to get it to pull data from ':user/plays.db' instead of one central
# db. In hindsight, as with everything else, that would have been a better idea.
#
# I basically monkey-patch Play to give us semi-nice to use methods (semi-
# because I would rather not have to pass in @user everytime).

gem 'sass'; require 'sass'
require 'haml'
require 'json'
require 'sinatra'
require 'pathname'
require 'dm-core'
require_relative 'app/models'
require_relative '../_common/global'

set :views, File.dirname(__FILE__) + '/app'


# Complains if the default adapter is not set!
DataMapper.setup(:default, 'sqlite::memory:')

class User
  PAGE_SIZE = 50

  def initialize(name)
    @name = name
  end

  def data
    @data ||= JSON.parse File.read(path + 'data.json')
  end

  def path
    ROOT + 'last.fm' + @name
  end

  def url
    "/" + @name
  end

  def sorted_artists
    @sorted_artists ||= artists.sort_by {|a| -a.plays_count }
  end

  def artists(opts={})
    query(Artist, opts) {|results|
      load_raw_for(results)
    }
  end

  def sorted_albums
    @sorted_albums ||= albums.sort_by {|a| -a.plays_count }
  end

  def albums(opts={})
    query(Album, opts).tap {|results|
      load_raw_for(results)
    }
  end

  # @example The track played last
  #
  #   user.plays(limit: 1, order: :date.desc).first
  #
  def plays(opts={})
    query(Play, opts).tap {|results|
      load_raw_for(results)
    }
  end

  def page(num, opts={})
    opts.merge! limit: PAGE_SIZE,
                offset: PAGE_SIZE * num,
                order: :date.desc

    plays opts
  end

  private

  def load_raw_for(results)
    results.each do |result|
      result.load_raw(self)
    end
  end

  # @see http://rubydoc.info/gems/dm-core/1.1.0/DataMapper/Query
  def query(model, options={})
    query = DataMapper::Query.new(repo, model, options)
    repo.read(query)
  end

  def repo
    return @repo if @repo
    DataMapper.setup(@name.to_sym, "sqlite://#{path.realpath + 'plays.db'}")
    @repo = DataMapper.repository(@name.to_sym)
  end
end

module Raw
  def load_raw(user)
    return true if @__raw
    id = attribute_get(:id)
    repo = user.send(:repo)
    @__raw = repo.adapter.select('SELECT * FROM plays WHERE id = ' + id.to_s).first;
  end

  def raw
    @__raw
  end
end


class Artist
  include Raw

  def plays_count
    @plays_count ||= plays.size
  end
end

class Album
  include Raw

  def plays_count
    @plays_count ||= plays.size
  end
end

class Play
  include Raw

  def artist(user)
    id = raw.artist_id
    user.artists(offset: id - 1, limit: 1).first
  end

  def album(user)
    id = raw.album_id
    user.albums(offset: id - 1, limit: 1).first
  end
end


get '/user/:name/?' do
  @user = User.new(params[:name])

  haml :user
end

get '/user/:name/artists/?' do
  @user    = User.new(params[:name])
  @artists = @user.artists

  haml :artists
end

get '/user/:name/albums/?' do
  @user   = User.new(params[:name])
  @albums = @user.albums

  haml :albums
end

get '/user/:name/plays/?' do
  @user  = User.new(params[:name])
  @page  = 0
  @plays = @user.plays.page(@page)

  haml :plays
end

get '/user/:name/plays/page/:page/?' do
  @user  = User.new(params[:name])
  @page  = params[:page].to_i
  @plays = @user.plays.page(@page)

  redirect @user.url + '/plays' if @page == 0
  haml :plays
end

get '/styles.css' do
  sass :styles
end
