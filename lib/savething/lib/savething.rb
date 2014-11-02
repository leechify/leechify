require "monitor"
require "stringio"

# Savething is a fork of https://github.com/Burgestrand/plaything/ which saves
# the raw pcm stream instead of playing it.
class Savething
  attr_accessor :pcm_stream

  Error = Class.new(StandardError)
  Formats = {
    [ :int16, 1 ] => :mono16,
    [ :int16, 2 ] => :stereo16,
  }

  # Open the default output device and prepare it for playback.
  def initialize(format = { sample_rate: 44100, sample_type: :int16, channels: 2 })
    @monitor = Monitor.new
    pcm_stream_clear

    self.format = format
  end

  def pcm_stream_clear
    @pcm_stream = StringIO.new
  end

  # Start playback of queued audio.
  #
  # @note You must continue to supply audio, or playback will cease.
  def play
  end

  # Pause playback of queued audio. Playback will resume from current position when {#play} is called.
  def pause
  end

  # Stop playback and clear any queued audio.
  #
  # @note All audio queues are completely cleared, and {#position} is reset.
  def stop
  end

  # @return [Rational] how many seconds of audio that has been played.
  def position
    0
  end

  # @return [Integer] total size of current play queue.
  def queue_size
    0
  end

  # If audio is starved, and it has not been previously seen as starved, it
  # will return 1. However, if audio is starved and {#drops} has already
  # reported it as starved, it will return 0. Finally, if audio is not starved,
  # it always returns 0.
  #
  # @return [Integer] number of drops since previous call to {#drops}.
  def drops
    0
  end

  # @return [Boolean] true if audio stream has starved
  def starved?
    false
  end

  # @return [Hash] current audio format in the queues
  def format
    synchronize do
      {
        sample_rate: @sample_rate,
        sample_type: @sample_type,
        channels: @channels,
      }
    end
  end

  # Change the format.
  #
  # @note if there is any queued audio it will be cleared,
  #       and the playback will be stopped.
  #
  # @param [Hash] format
  # @option format [Symbol] sample_type only :int16 available
  # @option format [Integer] sample_rate
  # @option format [Integer] channels 1 or 2
  def format=(format)
    synchronize do
      $logger.debug("Savething") { "#{format}" }
      @sample_type = format.fetch(:sample_type)
      @sample_rate = Integer(format.fetch(:sample_rate))
      @channels    = Integer(format.fetch(:channels))

      @sample_format = Formats.fetch([@sample_type, @channels]) do
        raise TypeError, "unknown sample format for type [#{@sample_type}, #{@channels}]"
      end

      # 44100 int16s = 22050 frames = 0.5s (1 frame * 2 channels = 2 int16 = 1 sample = 1/44100 s)
      @buffer_size  = @sample_rate * @channels * 1.0
      # how many samples there are in each buffer, irrespective of channels
      @buffer_length = @buffer_size / @channels
      # buffer_duration = buffer_length / sample_rate
    end
  end

  # Queue audio frames for playback.
  #
  # @note this method is here for backwards-compatibility,
  #       and does not support changing format automatically.
  #       You should use {#stream} instead.
  #
  # @param [Array<Integer>] array of interleaved audio samples.
  # @return (see #stream)
  def <<(frames)
    stream(frames, format)
  end

  # Queue audio frames for playback.
  #
  # @param [Array<Integer>] array of interleaved audio samples.
  # @param [Hash] format
  # @option format [Symbol] :sample_type should be :int16
  # @option format [Integer] :sample_rate
  # @option format [Integer] :channels
  # @return [Integer] number of frames consumed (consumed_samples / channels), a multiple of channels
  def stream(frames, frame_format)
    synchronize do
      self.format = frame_format if frame_format != format

      if $logger.level == Logger::DEBUG
        $logger.debug("Savething") { "Current stream size: #{@pcm_stream.length}" }
      elsif $logger.level == Logger::INFO
        print "+"
      end

      @pcm_stream.write frames.take(frames.count).pack("s*")

      frames.count / @channels
    end
  end

  protected

  def buffers_processed
  end

  def synchronize
    @monitor.synchronize { return yield }
  end
end
