#!/usr/bin/env ruby
# encoding: utf-8

require 'optparse'
require 'fileutils'

require_relative "lib/savething/lib/savething"
require_relative "lib/support"


class Leechify
  def initialize
    Support::DEFAULT_CONFIG[:callbacks] = Spotify::SessionCallbacks.new($session_callbacks)
    Support.silenced = true
    @cfg = parseopts

    @session = Support.initialize_spotify!
    Spotify.session_set_private_session(@session, true)
    Spotify.session_preferred_bitrate(@session, 320)
    Spotify.session_preferred_offline_bitrate(@session, 320, true)
  end

  def parseopts
    # Parse the command line options
    attrs = {}
    options = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [OPTIONS] Spotify-URI..."
      opts.separator "Downloads the supplied Spotify-URIs"
      opts.separator "OPTIONS:"
      opts.on("-m [DIR]", "--musicdir [DIR]",
        "Specify where to download the songs to") do |musicdir|
        attrs[:dir] = musicdir
      end
      opts.on("-k", "--keep", "Keep pcm and jpg files after creating mp3") do
        attrs[:keep] = true
      end
      opts.on("-r", "--redownload", "Download already existing tracks again") do
        attrs[:redownload] = true
      end
      opts.on("-d", "--debug", "Enable debug output") do
        $logger.level = Logger::DEBUG
        Support.silenced = false
      end
      opts.on("-v", "--verbose", "Enable verbose output") do
        $logger.level = Logger::INFO
        Support.silenced = false
      end
      opts.on("-q", "--quiet", "Disable all output except warnings") do
        $logger.level = Logger::WARN
        attrs[:quiet] = true
      end
      opts.on("-h", "--help", "Show this help") do
        puts options
        exit 0
      end
      opts.separator "EXAMPLE:"
      opts.separator "    #{$0} spotify:track:6JEK0CvvjDjjMUBFoXShNZ"
    end
    options.parse!

    attrs[:dir] ||= "~/Music"
    if ARGV.empty?
      puts options
      exit 1
    else
      attrs[:links] = ARGV
    end
    attrs
  end

  def run
    @cfg[:links].each do |spotify_uri|
      link = Spotify.link_create_from_string(spotify_uri)
      if link.nil?
        $logger.error "Invalid URI. Aborting."
        abort
      end

      link_type = Spotify.link_type(link)
      if link_type == :track
        $logger.info("Run") { "Processing track #{spotify_uri}" }
        track = Spotify.link_as_track(link)
        play_save_track(track)
      elsif link_type == :album
        $logger.info("Run") { "Processing album #{spotify_uri}" }
        album = Spotify.link_as_album(link)
        play_save_album(album)
      elsif link_type == :playlist
        $logger.info("Run") { "Processing playlist #{spotify_uri}" }
        playlist = Spotify.playlist_create(@session, link)
        play_save_playlist(playlist)
      else
        $logger.error "Link was #{link_type} URI. Needs track, album or playlist. Aborting."
        abort
      end
    end

    Spotify.session_logout(@session)
    Support.poll(@session) { Spotify.session_connectionstate(@session) == :logged_out }
  end

  def play_save_track(track, dir=nil)
    Support.poll(@session) { Spotify.track_is_loaded(track) }
    $end_of_track = false

    # Metadata
    artists = []
    Spotify.track_num_artists(track).times do |num|
      artists[num] = Spotify.track_artist(track, num)
      Spotify.session_process_events(@session)
    end
    artist = artists.first
    artist_name = Spotify.artist_name(artist)

    album = Spotify.track_album(track)
    Spotify.session_process_events(@session)
    album_name = Spotify.album_name(album)
    album_year = Spotify.album_year(album)
    image_id = Spotify.album_cover(album, :large)
    image = Spotify.image_create(@session, image_id)

    Spotify.session_process_events(@session)
    track_name = Spotify.track_name(track)
    index = Spotify.track_index(track)
    duration = Spotify.track_duration(track)/1000

    available = Spotify.track_get_availability(@session, track)
    if available != :available
      $logger.warn("Skip") { "#{artist_name} - #{track_name} not available: #{available}" }
      return available
    end

    # Filename
    dir ||= @cfg[:dir]
    FileUtils.mkdir_p(File.expand_path(dir))

    name = "#{artist_name} - #{track_name}"
    sanename = name.gsub(/[^0-9a-zA-Z\.\-]/, "_")
    filename = File.expand_path("#{dir}/#{sanename}")

    if !@cfg[:redownload] && File.file?("#{filename}.mp3")
      $logger.info("Skip") { "#{artist_name} - #{track_name} already exists" }
      return :skip
    end

    # Play track
    Spotify.session_process_events(@session)
    Spotify.try(:session_player_play, @session, false)
    $streamout.pcm_stream_clear if $streamout.respond_to?("pcm_stream_clear")
    $logger.debug("Play") { "#{$streamout.inspect}" }

    Spotify.try(:session_player_load, @session, track)
    Spotify.try(:session_player_play, @session, true)

    $logger.info("Track") { %Q{#{artist_name} - #{album_name} (#{album_year}) - #{index} - #{track_name} (#{duration}s)}}
    Support.poll(@session) { $end_of_track }
    Spotify.try(:session_player_unload, @session)

    # Save stream
    if $streamout.respond_to?("pcm_stream")
      File.open("#{filename}.pcm", 'w') do |file|
        $streamout.pcm_stream.rewind
        file.binmode
        file.write $streamout.pcm_stream.read
      end

      Support.poll(@session) { Spotify.image_is_loaded(image) }
      File.open("#{filename}.jpg", 'w') do |file|
        file.write Spotify.image_data(image)
      end

      lame =  %Q{lame -r -V0} +
        %Q{ "#{filename}.pcm" "#{filename}.mp3"} +
        %Q{ --ta "#{artist_name} "} +
        %Q{ --tl "#{album_name}"} +
        %Q{ --ty "#{album_year}"} +
        %Q{ --tn "#{index}"} +
        %Q{ --tt "#{track_name}"} +
        %Q{ --ti "#{filename}.jpg"} +
        %Q{ --id3v2-only} +
        %Q{ --id3v2-utf16}
      lame += " -S" if @cfg[:quiet]
      $logger.debug lame
      system(lame)

      sleep(1)
      File.delete("#{filename}.pcm") unless @cfg[:keep]
      File.delete("#{filename}.jpg") unless @cfg[:keep]
    end
    return :success
  end

  def play_save_album(album)
    Support.poll(@session) { Spotify.album_is_loaded(album) }

    artist = Spotify.album_artist(album)
    artist_name = Spotify.artist_name(artist)
    album_name = Spotify.album_name(album)

    $dummy_callback = proc { }
    album_browse = Spotify.albumbrowse_create(@session, album, $dummy_callback, nil)
    Support.poll(@session) { Spotify.albumbrowse_is_loaded(album_browse) }

    num_tracks = Spotify.albumbrowse_num_tracks(album_browse)
    $logger.info("Album") {"#{artist_name} - #{album_name} (#{num_tracks} items)" }

    name = "#{artist_name}/#{album_name}"
    sanename = name.gsub(/[^0-9a-zA-Z\.\-\/]/, "_")
    dir = File.expand_path("#{@cfg[:dir]}/#{sanename}")

    num_tracks.times do |index|
      track = Spotify.albumbrowse_track(album_browse, index)
      play_save_track(track, dir)
    end
  end

  def play_save_playlist(playlist)
    Support.poll(@session) { Spotify.playlist_is_loaded(playlist) }

    playlist_name = Spotify.playlist_name(playlist)
    num_tracks = Spotify.playlist_num_tracks(playlist)
    $logger.info("Playlist") { "#{playlist_name} (#{num_tracks} items)" }

    name = playlist_name
    sanename = name.gsub(/[^0-9a-zA-Z\.\-]/, "_")
    dir = File.expand_path("#{@cfg[:dir]}/#{sanename}")

    num_tracks.times do |index|
      track = Spotify.playlist_track(playlist, index)
      play_save_track(track, dir)
    end
  end
end


$streamout = Savething.new
$session_callbacks = {
  log_message: proc do |session, message|
    $logger.info("Session-log") { message }
  end,

  logged_in: proc do |session, error|
    $logger.debug("Session-usr") { error.message }
  end,

  logged_out: proc do |session|
    $logger.debug("Session-usr") { "logged out!\n" }
  end,

  streaming_error: proc do |session, error|
    $logger.error("Session-err") { "streaming error %s" % error.message }
  end,

  start_playback: proc do |session|
    $logger.debug("Session-play") { "start playback" }
    $streamout.play
  end,

  stop_playback: proc do |session|
    $logger.debug("Session-play") { "stop playback" }
    $streamout.stop
  end,

  get_audio_buffer_stats: proc do |session, stats|
    stats[:samples] = $streamout.queue_size
    stats[:stutter] = $streamout.drops
    #$logger.debug("session-play") { "queue size [#{stats[:samples]}, #{stats[:stutter]}]" }
  end,

  music_delivery: proc do |session, format, frames, num_frames|
    if num_frames == 0
      $logger.debug("Session-play") { "music delivery audio discontuity" }
      $streamout.stop
      0
    else
      frames = FrameReader.new(format[:channels], format[:sample_type], num_frames, frames)
      consumed_frames = $streamout.stream(frames, format.to_h)
      $logger.debug("session-play") { "music delivery #{consumed_frames} of #{num_frames}" } if consumed_frames != num_frames
      consumed_frames
    end
  end,

  end_of_track: proc do |session|
    $end_of_track = true
    $logger.debug("session-play") { "end of track" }
    $streamout.stop
  end,
}


leech = Leechify.new
leech.run
