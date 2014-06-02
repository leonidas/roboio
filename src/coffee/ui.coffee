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

define ['jquery', 'utils'], ($, Utils) ->
  MESSAGE_BUFFER_SIZE = 5

  UI =
    videos: [
        elem:   $('#video img')
        msg:    $('#video textarea')
        width:  0 # Height received from robot, used to determine rescaling
        height: 0
        hide:   false
        msgheight: 0
        messages: []
      ,
        elem:   $('#template_matcher_video img')
        msg:    $('#template_matcher_video textarea')
        width:  0
        height: 0
        hide:   true
        msgheight: 0
        messages:  []
    ]

    device_selector:   null
    template_selector: null

    # Show message about hand control being lost (due to testing,
    # another user, or connection problem)
    showHandLost: ->
      $('.handlost', '#flash').show()
      $('.confirm',  '#flash').hide()
      $('#flash').show()

    # Show confirm dialog when about to get lock from another user
    showConfirmAcquire: ->
      $('.handlost', '#flash').hide()
      $('.confirm',  '#flash').show()
      $('#flash').show()

    hideFlash: ->
      $('#flash').hide()

    getTemplateName: ->
      name = prompt "Please enter a name for the template", ""
      return name

    getReferenceName: ->
      name = prompt "Please enter a name for the reference image", "Ref-#{Utils.currTime()}"
      return name

    setDeviceList: (devices, current) ->
      UI.device_selector ?= $('#device_selector')

      UI.device_selector.empty()
      if devices.length > 0
        UI.device_selector.append $("<option value='#{devices[i]}' data-ord='#{i}'>#{devices[i]}</option>") for i in [0..devices.length-1]
        $('option[value="' + current + '"]', UI.device_selector).attr 'selected', 'selected'
      else
        UI.device_selector.append $("<option selected='selected'>N/A</option>")
        UI.device_selector.attr 'disabled', 'disabled'

    setTemplates: (templates) ->
      UI.template_selector ?= $('#template_selector')

      current = $('option:selected', UI.template_selector).val()
      UI.template_selector.empty()
      if templates.length > 0
        UI.template_selector.append $("<option value='#{template}'>#{template}</option>") for template in templates
        $('option[value="' + current + '"]', UI.template_selector).attr 'selected', 'selected'
      else
        UI.template_selector.append $("<option selected='selected'>N/A</option>")
        UI.template_selector.attr 'disabled', 'disabled'

    __over_bounds: (index) ->
      if index >= UI.videos.length
        Utils.error "Trying to handle feed index #{index} but UI element not defined"
        true
      else
        false

    setVideoSource: (index, src, width, height, adjust_to_video = false) ->
      return if UI.__over_bounds index

      # Need to adjust size of the element
      if width != UI.videos[index].width || height != UI.videos[index].height
        th = height
        wh = width

        # This makes currently sense only for the 2nd stream placed under controls
        if adjust_to_video
          target_width = $('div.robotcontrols', '.controls').width()

          th = (target_width / width) * height
          wh = target_width

        UI.videos[index].width  = width
        UI.videos[index].height = height
        UI.videos[index].elem?.css('width', wh).css('height', th)
          .css('min-width', wh).css('min-height', th).end()

      UI.videos[index].elem?[0].src = src
      # Set also the source for Jcrop images if found
      UI.videos[index].elem?.parent().find('div > img').each (i, e) -> e.src = src

      # Show the element if hidden
      UI.videos[index].elem?.fadeIn() if UI.videos[index].hide && !UI.videos[index].elem?.is(':visible') && src != ''

      return

    removeVideoSource: (index) ->
      return if UI.__over_bounds index
      UI.videos[index].elem?.fadeOut(400, -> UI.setVideoSource index, '', 0, 0) if UI.videos[index].hide

    setMessage: (index, msg) ->
      return if UI.__over_bounds index
      return UI.removeMessage(index) unless msg? && msg.length > 0

      unless UI.videos[index].msg?.is(':visible')
        UI.videos[index].msg?.css('width', UI.videos[index].elem.width())
          .css('min-width', UI.videos[index].elem.width())
          .css('max-width', UI.videos[index].elem.width())
        UI.videos[index].msg?.css('display', 'block')

      # Do not add the message if it's the same as the previous message
      if UI.videos[index].messages.length == 0 || UI.videos[index].messages[0] != msg
        UI.videos[index].messages = [msg].concat UI.videos[index].messages
        UI.videos[index].messages = UI.videos[index].messages.slice(0,MESSAGE_BUFFER_SIZE)

      UI.videos[index].msg?.val UI.videos[index].messages.join "\r\n"
      if UI.videos[index].msg?.get(0).scrollHeight != UI.videos[index].msgheight
        UI.videos[index].msg?.css('height', 'auto')
        UI.videos[index].msg?.css('height', UI.videos[index].msg?.get(0).scrollHeight + 'px')
        UI.videos[index].msgheight = UI.videos[index].msg?.get(0).scrollHeight

    removeMessage: (index) ->
      return if UI.__over_bounds index
      UI.videos[index].msg?.hide()
