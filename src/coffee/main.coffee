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

require.config
  baseUrl: "/js/modules"
  paths:
    'jquery':       '../vendor/jquery.min'
    'bacon':        '../vendor/Bacon.min'
    'jcrop':        '../vendor/jquery.Jcrop'
    'select':       '../vendor/select2.min'
  shim:
    select:
      deps:         ['jquery']
    bacon:
      deps:         ['jquery']
      exports:      'Bacon'
    jcrop:
      deps:         ['jquery']
      exports:      'Jcrop'

require ['app'], (app) ->
  app.main()
