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

define ['jquery', 'bacon', 'jcrop', 'utils', 'ws', 'ui', 'testrun'], ($, Bacon, Jcrop, Utils, WS, UI, TR) ->
  $('.connlost .retry', '#error').text "#{Utils.RECONN_TIMEOUT / 1000}"

  ws = null
  # Is ws server connected?
  wsConnected  = new Bacon.Bus()

  jc_api = null   # Jcrop handle

  # Crop size
  CROP_SIZE = 100

  main = () ->
    connecting = false
    ws         = new WebSocket Utils.getWsUri()
    wscmd      = new WS ws

    frameIdx     = 0
    streamPaused = false
    wasReserved  = false
    template     = null

    # Keep the currently displayed image blobs here
    image_urls = []

    $cropMarker = $('.marker', '#video')

    stopCrop = (src) ->
      $cropMarker.hide()
      # Stop saving template whenever reservation state changes
      if jc_api?
        jc_api.destroy()
        jc_api = null

        # Upon reconnection we may need just a little more time
        if ws.readyState == 1
          wscmd.stopLiveTemplateMatching()
        else
          setTimeout (-> wscmd.stopLiveTemplateMatching()), 100

    clearVideos = ->
      for i in [0..UI.videos.length-1]
        UI.removeVideoSource i
        UI.removeMessage i
      for prevUrl in image_urls
        Utils.url.revokeObjectURL prevUrl if prevUrl?

    clearVideosFrom = (index) ->
      return unless index < image_urls.length

      for i in [index..image_urls.length-1]
        UI.removeVideoSource(i)
        UI.removeMessage(i)
        Utils.url.revokeObjectURL image_urls[i] if image_urls[i]?
      image_urls = image_urls.slice(0, index)

    reconnect = ->
      wsConnected.push false
      unless connecting
        Utils.warn "Reconnecting to WebSocket in #{Utils.RECONN_TIMEOUT / 1000} seconds"
        connecting = true
        setTimeout (() -> main()), Utils.RECONN_TIMEOUT

    ws.onclose = reconnect
    ws.onerror = reconnect
    ws.onopen  = ->
      clearVideos() # Possibly reconnecting, cleanup
      Utils.debug "Connected to WebSocket server"
      wsConnected.push true
      stopCrop()

    onCropSelect = (c)   ->
      template = x1: c.x, y1: c.y, x2: c.x2, y2: c.y2, idx: null
      wscmd.startLiveTemplateMatching template

    onCropChange = (c) ->
      # Set the center point to current location
      $cropMarker.show()
      $cropMarker.css 'top', Math.round(c.y + (c.y2 - c.y) / 2 - $cropMarker.height() / 2)
      $cropMarker.css 'left', Math.round(c.x + (c.x2 - c.x) / 2 - $cropMarker.width() / 2)

    onCropClear = ->
      template = null
      wscmd.stopLiveTemplateMatching()

    eyeStatusMsg    = (val) -> if val then 'Connected' else 'Not connected'
    handStatusClass = (msg) -> Utils.HAND_STATUS_CLASS[msg.hand_status]
    lockButtonText  = (val) -> if val then 'Release lock' else 'Acquire lock'
    # The lock release timer
    minutesToTime   = (val) ->
      text = ""
      if val?
        # Show rounded up minutes if  more than half a minute left
        if val > 0.5
          mins = Math.ceil val
          text = if mins == 1 then "#{mins} minute" else "#{mins} minutes"
        else
          secs = Math.ceil(val * 60 / 10) * 10
          if wasReserved
            Utils.notify 'You are about to lose control of the robot' if secs == 30
          text = "#{secs} seconds"
      text
    boolToDisplay   = (type = 'block') -> (val) -> if val then type else 'none'
    # Keys enabled when hand is locked for execution
    lockModeKeys    = (char) -> ~['t', 'p'].indexOf char
    # Keys filtered always (to prevent sending useless messages when e.g. using
    # alt-tab to change between windows)
    unwantedKeys    = (ev) -> !~[17, 18, 9].indexOf ev.which # Ctrl, Alt, Tab
    keypressToChar  = (ev) -> String.fromCharCode(ev.which).toLowerCase()
    # Currently selected device index and name
    currentDevice   = ->
      opt =  $('option:selected', '#device_selector')
      index: opt.attr('data-ord'), name: opt.val()

    messages = Bacon.fromEventTarget(ws, 'message').map (msg) -> JSON.parse msg.data

    statuses  = messages.filter (msg) -> msg.type == Utils.MSG_TYPES.IN.STATUS
    images    = messages.filter((msg) -> msg.type == Utils.MSG_TYPES.IN.STREAM).filter(-> !streamPaused)
    positions = messages.filter((msg) -> msg.type == Utils.MSG_TYPES.IN.POS).map('.position')

    videofeed       = images.map (msg) -> msg.feeds?[0]
    secondary_feeds = images.map (msg) -> msg.feeds?.slice(1)

    lock_release = images.map (msg) -> msg.lock_release

    # Current status of the hand controller
    handStatus   = statuses.map('.hand_status').toProperty(Utils.HAND_STATUS.NOT_CONNECTED)
    # Does server have connection to the robot eye?
    eyeConnected = statuses.map('.eye_status').toProperty(false)
    # Is hand reserved to current user?
    handReserved = handStatus.map((val) -> val == Utils.HAND_STATUS.LOCKED_FOR_CURR_USER).toProperty(false)
    # Is hand reserved to someone else?
    handReservedBySomeone = handStatus.map((val) -> val == Utils.HAND_STATUS.LOCKED_FOR_USER).toProperty(false)
    # Is hand free to take?
    handFree     = handStatus.map((val) -> val == Utils.HAND_STATUS.FREE).toProperty(false)
    # Hand locked for test execution
    handLocked   = handStatus.map((val) -> val == Utils.HAND_STATUS.LOCKED_FOR_TEST_RUN).toProperty(false)
    # Is a device currently being selected?
    allowControl = statuses.map('.disable_ctrls').not().toProperty()

    set_feed_image = (index, feed, adjust_to_video = false) ->
      if feed.png? and feed.png != ''
        imgUrl = Utils.base64ToObjectURL feed.png # create a blob
        UI.setVideoSource index, imgUrl, feed.width, feed.height, adjust_to_video # show it
        Utils.url.revokeObjectURL image_urls[index] if image_urls[index]? # revoke old
        image_urls[index] = imgUrl # store new blob to cache

    # Keep the previous objectURL to prevent single 404 and a black flash when
    # starting cropping. It will set the source from the parent image and if
    # it has been revoked then the screen turns black for one frame.
    # Now, handle the main video feed
    videofeed.onValue (feed) ->
      return unless feed?

      frameIdx = feed.index
      if feed.updated
        set_feed_image 0, feed
        UI.setMessage 0, feed.message

    # Handle secondary feeds separately. add .filter(handReserved) to show them
    # only to the user currently in control
    secondary_feeds.onValue (feeds) ->
      for feed, i in feeds
        index = i + 1 # The first feed has been removed
        if feed.updated
          set_feed_image index, feed, index == 1
          UI.setMessage index, feed.message

      # Do we now have less video sources than previously? If so, we consider
      # that there is no need to show those anymore so they can be revoked and
      # the video source elements hidden. Again, take the removed element into account
      clearVideosFrom feeds.length + 1 if feeds.length + 1 < image_urls.length

    #
    # Indicators
    #

    # Set eye status indicator
    eyeConnected.assign $('.eyestatus'), 'toggleClass', 'connected' # CSS class
    eyeConnected.map(eyeStatusMsg).assign $('.eyestatus'), 'text' # Text
    # Lost eye connection, clear the video to prevent old image flashing when reconnected
    eyeConnected.onValue (val) -> clearVideos() unless val


    # Set hand status indicator
    statuses.map(handStatusClass).onValue (cls) -> $('.handstatus').removeClass('na ok nok warn').addClass cls # CSS class
    statuses.map('.hand_state').assign $('.handstatus'), 'text' # Text

    # Hand lock release timer visibility
    lock_release.map(boolToDisplay()).assign $('.lock_release'), 'css', 'display'
    # Lock release time
    lock_release.map(minutesToTime).assign $('p.lock_release.time'), 'text'

    # Show main if both eye and WS are connected (and the other way round for error)
    show_main = wsConnected.toProperty().and(eyeConnected)
    show_main.not().map(boolToDisplay()).assign $('#error'), 'css', 'display'
    show_main.map(boolToDisplay()).assign $('#main'), 'css', 'display'

    # Error message within the #error dialog. If WS is connected then the error
    # may show information only about eye so we can decide what to show based
    # ws connection status
    wsConnected.toProperty().not().map(boolToDisplay()).assign $('.connlost',  '#error'), 'css', 'display'
    wsConnected.toProperty().map(boolToDisplay()).assign $('.streamingsource', '#error'), 'css', 'display'

    # Paused stream
    images.map(-> streamPaused).map(boolToDisplay()).assign $('span.paused', 'div.locked'), 'css', 'display'

    handReserved.onValue (reserved) ->
      stopCrop()

      # Inform about having lost control if needed
      if !reserved && wasReserved
        UI.showHandLost()
        Utils.notify 'You have lost control of the robot'
      # Clear secondary feeds if lost control of the robot
      clearVideosFrom 1 unless reserved

      wasReserved = reserved

    # Position of the robot
    positions.map('.x').assign    $('input[name="x_coord"]'), 'val'
    positions.map('.y').assign    $('input[name="y_coord"]'), 'val'
    positions.map('.z').assign    $('input[name="z_coord"]'), 'val'
    positions.map('.alfa').assign $('input[name="angle"]'),   'val'
    positions.map((pos) -> "#{pos.x},#{pos.y},#{pos.z},#{pos.alfa}").assign $('input[name="current_pos_str"]'), 'val'

    #
    # Controls
    #

    # Acquire lock -button enabled/disabled (if hand can be reserved and
    # device is not currently being selected)
    handStatus.map((val) -> val >= Utils.HAND_STATUS.LOCKED_FOR_CURR_USER).and(allowControl).not().assign $('#acquire_lock'), 'attr', 'disabled'
    # Lock button says either Acquire or Release lock
    handReserved.map(lockButtonText).assign $('#acquire_lock'), 'text'
    # Other buttons etc. are enabled only if lock is acquired
    handReserved.and(allowControl).not().assign $('select, .requirescontrol', 'td.controls'), 'attr', 'disabled'

    statuses.onValue (msg) ->
      UI.setDeviceList msg.devices, msg.current_device
      UI.setTemplates msg.templates
      # We can now initialize the test run tab when the devices are in place.
      # This is a bit weird but it also makes no sense to deliver the duts
      # applications on every websocket message.
      TR.init()

    # Show controls visible during test execution
    handLocked.map(boolToDisplay('inline-block')).assign $('div.locked'), 'css', 'display'
    # Show controls visible when test is not being executed
    handLocked.not().map(boolToDisplay('inline-block')).assign $('div.not_locked'), 'css', 'display'

    # Unset features available only during test run
    handLocked.onValue (locked) -> streamPaused = false if not locked

    #
    # Click/keypress handlers
    #
    assign_handlers = (handStatusStream) ->
      lockButton = $('#acquire_lock').off('click').asEventStream 'click'
      # Hand reserved -> release it
      lockButton.filter(handReserved).onValue -> wasReserved = false; wscmd.releaseHand()
      # Hand free -> acquire lock
      lockButton.filter(handFree).onValue ->
        wscmd.reserveHand()
        # Also fetch the current position if already on calibration tab
        wscmd.getPosition() if $('a.active', 'ul.tabs').attr('data-tab') == 'calibration'
      # Hand reserved to someone else -> steal it
      lockButton.filter(handReservedBySomeone).onValue -> UI.showConfirmAcquire()
      # Ask for desktop notifications rights
      lockButton.onValue Utils.requestNotifications

      # Set visual data source if not currently locked for test exec.
      startCam = $('#start_camera').off('click').asEventStream 'click'
      startCam.filter(handLocked.not()).onValue -> wscmd.startCamera()

      # Confirm acquire lock from another user
      $('.getcontrol', '#flash').off('click').on 'click', (ev) ->
        wscmd.setFindTemplate '' # Stop looking for a template, just in case
        wscmd.reserveHand()
        UI.hideFlash()

      # Close dialog
      $('.close', '#flash').off('click').on 'click', ->
        Utils.hideNotification()
        UI.hideFlash()
      keypresses   = $(window).off('keydown').asEventStream('keydown').filter(unwantedKeys)
      # Stream of allowed chars when hand is locked for test execution
      lockControls = keypresses.filter(handLocked).map(keypressToChar).filter(lockModeKeys)
      # Send keypresses to backend if we have control of the hand
      keypresses.filter(handReserved).onValue (ev) -> wscmd.sendKey ev, frameIdx
      # Close dialogs with esc if any are visible
      keypresses.filter((ev) -> ev.keyCode == 27).onValue ->
        Utils.hideNotification()
        UI.hideFlash()

      # Handle the allowed chars in test execution mode
      lockControls.onValue (char) ->
        streamPaused = !streamPaused if char == 'p'

      # Clicks on the "video"
      clicks = $('#video img').off('click').asEventStream('click').map Utils.fixEventCoordinates
      clicks.filter(handReserved).onValue (ev) -> wscmd.sendClick ev, frameIdx

      # Device selector
      devSelecting = $('#device_selector').off('change').asEventStream('change').map '.originalEvent.target.value'
      devSelecting.filter(handReserved).onValue ->
        TR.reset_apps_list()
        wscmd.setDevice( $('#device_selector').val() )

      # Template matching selector
      findTemplate = $('#template_selector').off('change').asEventStream('change').map '.originalEvent.target.value'
      findTemplate.filter(handReserved).onValue wscmd.setFindTemplate

      # Reset device calibration
      $('#reset_device_calibration').off('click').asEventStream('click')
        .filter(handReserved).map(currentDevice).onValue wscmd.resetDeviceCalibration

      # Move robot buttons (x/y/z/a)
      calibratebuttons = $('button', '.move_robot').off('click').asEventStream('click').map('.originalEvent.target')
      calibratebuttons.filter(handReserved).onValue (ev) ->
        distance =
          parseFloat($('input[name="distance"]:checked').val()) *
          parseFloat($(ev).attr('data-val'))
        wscmd.moveCoord $(ev).attr('data-cmd'), distance

      # Prevent window level keypress handler to catch events when
      # typing values to the robot location inputs
      $('input', '.current_position').off('keydown').on 'keydown', (ev) ->
        ev.stopPropagation()
        $f = $(this)
        $f.css 'border-color', if isNaN parseFloat $f.val() then 'red' else '#cccccc'

      # Disable keypress handler from input controls with disable_keys class
      $('input.disable_keys').off('keydown').on 'keydown', (ev) -> ev.stopPropagation()

      # Create the position object from event
      get_position = (ev) ->
        msg = {}
        for f in $(ev).parent().parent().parent().find('input')
          $f = $(f)
          $f.val $f.val().replace /,/g, '.'
          msg[$f.attr('data-coord')] = parseFloat $f.val()
        msg

      # Set position -button
      $('#set_position').off('click').asEventStream('click')
        .map('.originalEvent.target')
        .filter(handReserved)
        .map(get_position)
        .filter((msg) ->
          for k, v of msg
            return false if isNaN(v)
          return true
        ).onValue (msg) -> wscmd.setPosition msg

      # Save reference button
      saveReference = $('#save_reference').off('click').asEventStream('click')
      saveReference.filter(handReserved).onValue ->
        fidx = frameIdx # Store now so we store the frame that was visible when clicked
        name = UI.getReferenceName()
        wscmd.saveReference x1: null, y1: null, x2: null, y2: null, idx: fidx, name if name != null

      $('#save_template').off('click').asEventStream('click').filter(handReserved).onValue ->
        if jc_api?
          stopCrop()
          if template?
            template.idx = frameIdx
            name = UI.getTemplateName()
            wscmd.saveReference template, name if name != null

        else
          template = null
          # Create Jcrop with initial selection
          jc_api = $.Jcrop '#video img',
            onSelect:  onCropSelect
            onRelease: onCropClear
            onChange:  onCropChange
            setSelect: [
              UI.videos[0].width / 2 - CROP_SIZE / 2
              UI.videos[0].height / 2 - CROP_SIZE / 2
              UI.videos[0].width / 2 + CROP_SIZE / 2
              UI.videos[0].height / 2 + CROP_SIZE / 2
            ]

      # Tabs
      $('a', '.robotcontrols .tabs').off('click').on 'click', (e) ->
        e.preventDefault()
        target = $(this).attr 'data-tab'
        # Clicking the same tab again
        return if target == $('.tab:visible').attr('data-tab')

        wscmd.getPosition() if target == 'calibration'

        $(this).addClass('active').parent().siblings().find('a').removeClass('active')
        $('div.tab[data-tab="' + target + '"]', '.control_container').show().siblings().hide()
        true

    assign_handlers handStatus

  { main }
