#!/usr/bin/env ruby

require 'json'
require 'pathname'
require 'sinatra/base'
require 'pp'
require 'time'
require 'haml'
require 'launchy'

class Hall::Facebook::Serve < Sinatra::Base

  set :public_folder, File.dirname(__FILE__)
  set :views, File.dirname(__FILE__) + '/app'

  def format_time(str)
    Time.parse(str).strftime('%B %Y')
  end

  class Photo
    def initialize(dir)
      @dir = dir
    end

    def data
      JSON.parse File.read(@dir + '/data.json')
    end

    def path
      '/' + @dir.split('/')[1..-1].join('/')
    end

    def thumb
      path + '/thumb.jpg'
    end

    def photo
      path + '/photo.jpg'
    end

    def url
      '/' + path.split('/')[1..-1].join('/')
    end
  end

  class Album
    def initialize(dir)
      @dir = Pathname.new(dir)
    end

    def data
      return {} unless (@dir + 'data.json').exist?
      JSON.parse File.read(@dir + 'data.json')
    end

    def photos
      @photos ||= Dir[@dir + '*/']
        .map {|p| Photo.new(p) }
        .sort_by {|p| p.data['created_time'] }
    end

    def cover
      photos.first
    end

    def url
      '/' + @dir.to_s.split('/')[1..-1].join('/')
    end

    def find(photo_id)
      p = Dir[@dir + photo_id].map {|p| Photo.new(p) }
      return nil if p.empty?
      p.first
    end
  end

  class User
    def self.all
      Dir[ROOT + 'facebook' + '*/']
        .map {|u| User.new(u.split('/').last) }
        .reject {|u| u.id == "app" }
        .sort_by {|u| u.data['name'] }
    end

    attr_reader :id

    def initialize(id)
      @id = id
    end

    def albums
      @albums ||= Dir[ROOT + 'facebook' + @id + 'photos' + '*']
        .map {|a| Album.new(a) }
        .reject {|a| a.photos.empty? }
        .sort_by {|a| a.data['updated_time'] }
    end

    def photos_of
      return nil unless (ROOT + 'facebook' + @id + 'photos_of').exist?
      Album.new(ROOT + 'facebook' + @id + 'photos_of')
    end

    def data
      JSON.parse File.read(ROOT + 'facebook' + @id + 'data.json')
    end

    def url
      '/' + id
    end

    def find_by_name(name)
      albums.find {|a| a.data['name'] == name }
    end

    def find(album_id)
      a = Dir[ROOT + 'facebook' + @id + 'photos' + album_id].map {|a| Album.new(a) }
      return nil if a.empty?
      a.first
    end
  end


  get '/' do
    @users = User.all
    haml :index
  end

  get '/:id/?' do
    @me = User.new(params[:id])
    haml :user
  end

  get '/:id/photos_of/?' do
    @me = User.new(params[:id])

    @album = @me.photos_of
    return "404 album not found" if @album.nil?

    @album.instance_variable_set(:@__me, @me)
    def @album.data
      {'name' => "Photos of #{@__me.data['name'].split(' ').first}"}
    end

    haml :album
  end

  get '/:id/photos_of/:photo/?' do
    @me = User.new(params[:id])

    @album = @me.photos_of
    return "404 album not found" if @album.nil?

    @album.instance_variable_set(:@__me, @me)
    def @album.data
      {'name' => "Photos of #{@__me.data['name'].split(' ').first}"}
    end

    @photo = @album.find(params[:photo])
    return "404 photo not found" if @photo.nil?

    haml :photo
  end

  get '/:id/photos/:album/?' do
    @me = User.new(params[:id])

    @album = @me.find(params[:album])
    return "404 album not found" if @album.nil?

    haml :album
  end

  get '/:id/photos/:album/:photo/?' do
    @me = User.new(params[:id])

    @album = @me.find(params[:album])
    return "404 album not found" if @album.nil?

    @photo = @album.find(params[:photo])
    return "404 photo not found" if @photo.nil?

    haml :photo
  end
end

class Hall::Facebook
  command :serve do
    action do
      sinatra_options = {
        :port => '4567',
        :bind => 'localhost',
      }

      Serve.run!(sinatra_options) do |server|
        ::Launchy.open("http://localhost:4567/")
      end
    end
  end
end
