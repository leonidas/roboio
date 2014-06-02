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

define ->

  Utils =
    url: (window.webkitURL || window.URL)

    LOG_LEVEL:      0
    RECONN_TIMEOUT: 10000

    # Log levels
    level:
      debug: 0
      warn:  1
      err:   2

    # WebSocket message types
    MSG_TYPES:
      IN:
        STATUS: 0
        STREAM: 1
        POS:    2
      OUT:
        EVENT:             0   # Keypress, click
        LOCK:              1   # Acquire, release
        DEVICE:            2   # Select device
        TEMPLATE:          4   # Start matching selected template
        SAVE:              5   # Save reference/template
        START_CAMERA:      6   # Start robot camera
        START_MATCHING:    7   # Start live matching when creating a template
        STOP_MATCHING:     8   # Stop live matching (save/cancel create template)
        GET_POSITION:      9   # Get current position of the robot
        SET_POSITION:      10  # Set the position of the robot
        MOVE_COORD:        11  # Move the robot along the selected coordinate
        RESET_CALIBRATION: 12  # Reset the device calibration

    # Robot hand statuses
    HAND_STATUS:
      NOT_CONNECTED:        0
      LOCKED_FOR_TEST_RUN:  1
      LOCKED_FOR_USER:      2
      LOCKED_FOR_CURR_USER: 3
      FREE:                 4

    HAND_STATUS_CLASS:
      0: 'nok'
      1: 'nok'
      2: 'warn'
      3: 'ok'
      4: 'ok'

    prev_notification_time: null
    prev_notification_obj:  null

    # Get WebSocket connection URI
    getWsUri: ->
      port = window.location.port
      # For development purposes -- if using livereload, change WS port number
      if port == '6001' then port = '3120'
      port = if port then ":#{port}" else ""
      return "ws://#{window.location.hostname}#{port}#{window.location.pathname}/"

    base64ToObjectURL: (dat) ->
      # To prevent image caching (and thus memory leaks) we
      # transform the base64 encoded data into an ArrayBuffer
      # and generate an object-url for it. This lets us control
      # deallocation explicitly by calling revokeObjectURL when
      # the image is no longer needed.

      # Decode the base64 string into binary
      imageData = atob(dat)

      # Initialize an empty array buffer
      arraybuffer = new ArrayBuffer(imageData.length);

      # Write into the array buffer using an unsigned byte view
      view = new Uint8Array(arraybuffer);
      for i in [0..imageData.length-1]
        view[i] = imageData.charCodeAt(i) & 0xff

      # Initialize a binary blob data and create the
      # object-url that can be used in an image element.
      # Notice: If support for older browsers is needed then [view.buffer]
      # , i.e. ArrayBuffer, should be passed to Blob constructor. It is
      # however deprecated and newer browser versions will fill console
      # with warnings.
      blob = new Blob([view], {type: 'image/png'})
      return Utils.url.createObjectURL(blob)

    fixEventCoordinates: (ev) ->
      # Firefox - http://bugs.jquery.com/ticket/8523
      if typeof(ev.offsetX) == "undefined" || typeof(ev.offsetY) == "undefined"
        tos        = $(ev.target).offset()
        ev.offsetX = ev.pageX - tos.left
        ev.offsetY = ev.pageY - tos.top

      return ev

    currTime: ->
      d = new Date()
      return "#{d.getFullYear()}-#{d.getMonth()}-#{d.getDate()}_#{d.getHours()}#{d.getMinutes()}#{d.getSeconds()}"

    requestNotifications: ->
      return unless Notification?
      unless Notification.permission == "granted"
        Notification.requestPermission (permission) ->
          # Apparently some issues with Chrome, making sure it stores the response
          # https://developer.mozilla.org/en-US/docs/Web/API/notification#Example
          unless 'permission' in Notification
            Notification.permission = permission

    notify: (msg) ->
      return unless Notification?
      if Utils.prev_notification_time?
        # If last notification was shown less thant 10 seconds ago, do not show
        if (new Date().getTime() - Utils.prev_notification_time) / 1000 <= 10
          return
      Utils.prev_notification_time = new Date().getTime()

      # We don't ask again - user was asked for rights when he clicked
      # the acquire button, if he chose no then so be it
      if Notification.permission == "granted"

        Utils.prev_notification_obj?.close()
        Utils.prev_notification_obj =
          new Notification "Robos",
            body: msg
        Utils.prev_notification_obj.onclick = ->
          window.focus()
          @close()

    hideNotification: -> Utils.prev_notification_obj?.close()

    log: (level, msg...) ->
      if console?
        if level >= Utils.LOG_LEVEL
          console.log msg...

    debug: (msg...) -> Utils.log Utils.level.debug, msg
    warn:  (msg...) -> Utils.log Utils.level.warn,  msg
    err:   (msg...) -> Utils.log Utils.level.err,   msg
