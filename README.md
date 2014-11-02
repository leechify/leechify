leechify
========
Script to download songs, albums and playlists over the Spotify C API and save them as MP3.

![](http://i.imgur.com/ekBu9v4.png)

Requirements
------------
* Spotify Premium Account
* Ruby
* [LAME](http://lame.sourceforge.net/)

Install
-------
* Download your [Spotify application key](https://devaccount.spotify.com/my-account/keys/) in binary format to this folder
* Install the required ruby gems with `bundle install`

Usage
-----
```
Usage: ./leechify.rb [OPTIONS] Spotify-URI...
Downloads the supplied Spotify-URIs
OPTIONS:
    -m, --musicdir [DIR]             Specify where to download the songs to
    -k, --keep                       Keep pcm and jpg files after creating mp3
    -r, --redownload                 Download already existing tracks again
    -d, --debug                      Enable debug output
    -v, --verbose                    Enable verbose output
    -q, --quiet                      Disable all output except warnings
    -h, --help                       Show this help
EXAMPLE:
    ./leechify.rb spotify:track:6JEK0CvvjDjjMUBFoXShNZ
```
