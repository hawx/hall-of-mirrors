#!/usr/bin/env ruby

# Steps:
#  - download and store original photos and their "640x" versions
#  - download and store contents of `flickr.photos.getInfo` as a JSON file
#  - generate a photostream, dynamically, using sinatra

require 'fileutils'
require 'json'
require 'pathname'
require 'open-uri'
require 'pp'
require 'clive'
require 'flickraw'
require 'seq/paged'


class FlickRaw::Response
  # The built in #to_hash method doesn't do this deep stuff!
  def to_h
    h = to_hash.map {|k,v|
      if v.respond_to?(:to_h)
        [k, v.to_h]
      elsif v.respond_to?(:map) && v.all? {|obj| obj.respond_to?(:to_h) }
        [k, v.map(&:to_h)]
      else
        [k, v]
      end
    }
    Hash[h]
  end
end

module Hall::Flickr::Update
  module Helper extend self
    def authenticate
      unless Config.has?(:flickr)
        puts "You must run flickr/init to authenticate!"
        exit
      end

      flickr.access_token = Config.get(:flickr, :access_token)
      flickr.access_secret = Config.get(:flickr, :access_secret)
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


  class Photo
    include Writer

    def initialize(user, data)
      @user = user
      @data = data
    end

    def id
      @data['id'].to_s
    end

    def data
      @__data ||= flickr.photos.getInfo(photo_id: id).to_h
    end

    def exif
      @__exif ||= flickr.photos.getExif(photo_id: id).to_h
    rescue FlickRaw::FailedResponse
      @__exif = false
    end

    def to_json
      JSON.pretty_generate data
    end

    def path
      @user.path + "photos" + id
    end

    def thumb_url
      @data['url_z']
    end

    def original_url
      @data['url_o']
    end

    def self.thumb
      Proc.new do |obj, wr|
        open obj.thumb_url do |f|
          name = 'photo_z.jpg'
          File.write(obj.path + name, f.read)
          name
        end
      end
    end

    def self.original
      Proc.new do |obj, wr|
        open obj.original_url do |f|
          name = "photo_o.#{obj.data['originalformat']}"
          File.write(obj.path + name, f.read)
          name
        end
      end
    end

    writeable :data, 'data.json', :data

    writeable :exif, 'exif.json', :exif do |obj|
      obj.exif
    end

    writeable :thumb, 'photo_z.jpg', thumb do |obj|
      obj.thumb_url
    end

    writeable :original, nil, original do |obj|
      obj.original_url && Pathname.glob(obj.path + 'photo_o.*').size == 0
    end
  end

  class Favorite
    include Writer

    def initialize(user, data)
      @user = user
      @data = data
    end

    def id
      @data['id'].to_s
    end

    def path
      @user.path + 'favorites' + id
    end

    def data
      @data.to_h
    end

    writeable :fave, 'data.json', :data
  end

  class Set
    include Writer

    def initialize(user, data)
      @user = user
      @data = data
    end

    def id
      @data['id'].to_s
    end

    def title
      @data['title']
    end

    def photos
      @photos ||= flickr.photosets.getPhotos(photoset_id: id)['photo']
        .map {|hsh| hsh['id']}
    end

    def data
      @data.to_h.merge(photos: photos)
    end

    def path
      @user.path + "sets" + id
    end

    writeable :set, 'data.json', :data
  end

  class User
    include Writer

    def initialize(id)
      @id = id.to_s
    end

    def path
      ROOT + 'flickr' + @id
    end

    def photos
      Seq::Paged.new do |page|
        opts = {
          user_id:  @id,
          per_page: 500, # max allowed by flickr
          page:     page,
          extras:   'url_z,url_o'
        }

        flickr.people.getPhotos(opts).to_a.map {|data| Photo.new(self, data) }
      end
    end

    def sets
      Seq::Paged.new do |page|
        opts = {
          user_id:  @id,
          per_page: 500,
          page:     page
        }

        flickr.photosets.getList(opts).to_a.map {|data| Set.new(self, data) }
      end
    end

    def favorites
      Seq::Paged.new do |page|
        opts = {
          user_id:  @id,
          per_page: 500,
          page:     page,
          extras:   'url_z,url_o'
        }

        flickr.favorites.getList(opts).to_a.map {|data|
          owner = User.new(data['owner'])
          [owner, Photo.new(owner, data), Favorite.new(self, data)]
        }.flatten
      end
    end

    def data
      flickr.people.getInfo(user_id: @id).to_h
    end

    writeable :user, 'data.json', :data
  end
end


class Hall::Flickr
  command :update do
    bool :q, :quick,   'Stop writing photos/sets/faves on first skipped'
    bool :force_photo, 'Force overwrite of photo data and images'
    bool :force_info,  'Force overwrite of photo info'
    bool :force_set,   'Force overwrite of set data'
    bool :force_fave,  'Force overwrite of fave data'

    action do
      FlickRaw.api_key = ENV['FLICKR_KEY']
      FlickRaw.shared_secret = ENV['FLICKR_SECRET']

      Update::Helper.authenticate
      Update::Helper.test_login

      break_on_skip = get(:quick)

      overwrite = {}
      overwrite.merge!(info: true)                              if get(:force_info)
      overwrite.merge!(exif: true, thumb: true, original: true) if get(:force_photos)
      overwrite.merge!(set:  true)                              if get(:force_set)
      overwrite.merge!(user: true)                              if get(:force_user)
      overwrite.merge!(fave: true)                              if get(:force_fave)

      user = Update::User.new(Update::Helper.login['id'])

      puts "User".bold
      user.write(overwrite)

      puts "Photos".bold
      user.photos.each do |photo|
        break unless photo
        break if !photo.write(overwrite) && break_on_skip
      end

      puts "Sets".bold
      user.sets.each do |set|
        break unless set
        break if !set.write(overwrite) && break_on_skip
      end

      puts "Favorites".bold
      user.favorites.each do |fave|
        break unless fave
        break if !fave.write(overwrite) && break_on_skip
      end

      puts "Done!".green
    end
  end
end
