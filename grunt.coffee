###
RoboIO, Web UI for test robots
Copyright (c) 2014, Intel Corporation.

This program is free software; you can redistribute it and/or modify it
under the terms and conditions of the GNU Lesser General Public License,
version 2.1, as published by the Free Software Foundation.

This program is distributed in the hope it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
more details.
###

module.exports = (grunt) ->
  grunt.initConfig
    pkgFile: 'package.json'

    coffee:
      compile:
        expand: true
        cwd:    'src/coffee'
        src:    '**/*.coffee'
        dest:   'public/js/modules'
        ext:    '.js'

    stylus:
      compile:
        files:
          "public/css/styles.css": "src/stylus/styles.styl"
          "public/css/roboio.css": "src/stylus/roboio.styl"
        options:
          compress: true

    watch:
      coffee:
        files: ["src/coffee/**/*.coffee"]
        tasks: ["coffee", "reload"]

      stylus:
        files: ["src/stylus/*.styl"]
        tasks: ["stylus", "reload"]

    reload:
      port: 6001
      proxy:
        host: 'localhost'
        port: 3120

  grunt.loadNpmTasks "grunt-reload"
  grunt.loadNpmTasks "grunt-contrib-coffee"
  grunt.loadNpmTasks "grunt-contrib-stylus"
  grunt.loadNpmTasks "grunt-contrib-watch"

  grunt.registerTask "default", ["coffee", "stylus", "reload", "watch"]
