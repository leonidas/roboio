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

# Testrun tab specific things

define ['jquery', 'select', 'utils'], ($, select2, Utils) ->
  dutconfigs  = $.parseJSON $('.duts', '#robodata').text()
  roboconfig  = $.parseJSON $('.robo', '#robodata').text()
  initialized = false

  click_disabled = ($e) ->
    disabled = $e.prop('disabled')
    # Enable (temporarily) since disabled elements cannot be clicked
    $e.prop('disabled', false).trigger('click').prop('disabled', disabled)

  # (re)set the apps list. This is done obviosly during initialization, but
  # also after changing device.
  reset_apps_list = ->
    curr_device = $('option:selected', '#device_selector').val()
    apps        = $.grep(dutconfigs, (e, i) -> e.name == curr_device)?[0]?.apps

    # Clear current optiosn
    $('#tr_apps').select2('data', null)
    $('#tr_apps').empty()
    if apps?
      apps = apps.sort (a,b) ->
        if a.name < b.name then return -1
        if a.name > b.name then return 1
        return 0

      # Generate new <option>s
      $apps = $.map apps, (app) ->
        e = $("<option value=\"#{app.name}\">#{app.name}</option>")
        e.prop('selected', true) if app.selected
        e

      $('#tr_apps').append $apps
      $('#tr_apps').select2 width: 'element'

  # Set the visibility of elements based on robot settings, and also set the
  # defined default values
  init_form_values = ->
    $('fieldset', 'div.testrun').show()
    $("tr[data-for]", 'div.testrun').hide()
    for key, val of roboconfig
      $row = $('tr[data-for="' + key + '"]').show()
      continue if key == 'APPS' # Special case, values are set separately
      $target = $row.find('input[data-param="' + key + '"]')
      switch $target.attr('type')
        when 'text'     then $target.val(val)
        when 'checkbox' then $target.prop('checked', val)
        when 'radio'
          # Radio buttons, click always since they likely have handlers
          $target = $row.find('input[data-param="' + key + '"][value="' + val + '"]')
          click_disabled $target

      # The field visibility is bound to a checkbox? If, then determine
      # the checked status from the value for the actual field. Same for div
      if val
        $row.find('input[type="checkbox"][data-show-param="' + key + '"], ' +
                  'input[type="checkbox"][data-show-div="'   + key + '"]').each (i, e) ->
          click_disabled $(e)

    # Then hide also fieldsets that have no visible table rows
    $('fieldset', 'div.testrun').each (i, e) ->
      visible_rows = 0
      $(e).find('tr[data-for]').each (j, r) ->
        visible_rows += 1 if $(r).css('display') != 'none'
      if visible_rows == 0
        $(e).hide()

  # Generate the query string to be called Jenkins with
  gen_start_params = ->
    params =
      group:  $('.current_group', '#robodata').text()
      robot:  $('.current_name',  '#robodata').text()
      DUT:    $('option:selected', '#device_selector').val()
      delay:  '0sec'

    # Go through VISIBLE lines and collect the data
    $('tr[data-for]:visible').each (i, e) ->
      $e = $(e).find('input[data-param], select[data-param]')
      $e.each (idx, elem) ->
        $elem = $(elem)
        key   = $elem.attr('data-param')
        $elem.attr('type', 'select') if $elem.prop('tagName').toLowerCase() == 'select'
        switch $elem.attr('type')
          when 'text','hidden'     then params[key] = $elem.val()
          when 'checkbox'
            params[key] = if $elem.is(':checked') then 'true' else 'false'
          when 'select'
            params[key] = $.map($elem.find('option:selected'), (opt) -> $(opt).val()).join(" ")
          when 'radio'
            params[key] = $(e).find('input[data-param="' + key + '"]:checked').val()

    params

  assign_handlers = ->
    # Clear all existing handlers first so we don't need to call off when
    # setting new ones (which would remove earlierly introduced handlers
    # if assigning more than one to the same element)
    $('input[type="checkbox"][data-show-param]').off('click')
    $('input[type="checkbox"][data-select-param]').off('click')
    $('input[type="checkbox"][data-show-div]').off('click')

    # Checkboxes that, when enabled, make defined input field visible
    $('input[type="checkbox"][data-show-param]').on 'click', (e) ->
      $this = $(this)
      vis   = if $this.is(':checked') then 'visible' else 'hidden'
      $('input[data-param="' + $this.attr('data-show-param') + '"]').css 'visibility', vis

    # Checkboxes that, when enabled, select another checkbox. When deselected
    # the other checkbox is deselected only if it has data-autoselected set to true
    $('input[type="checkbox"][data-select-param]').on 'click', (e) ->
      $this   = $(this)
      $target = $('input[data-param="' + $this.attr('data-select-param') + '"]')
      if $this.is(':checked')
        # If the target is not checked, check it and mark as autoselected
        unless $target.is(':checked')
          $target.attr 'data-autoselected', 'true'
          $target.prop 'checked', true
      else
        # Uncheck. If target was not autoset, do nothing
        if $target.attr('data-autoselected') == 'true'
          $target.prop 'checked', false
          $target.attr 'data-autoselected', 'false'
      true

    # Checkboxes showing divs
    $('input[type="checkbox"][data-show-div]').on 'click', (e) ->
      $this = $(this)
      $('div[data-div-name="' + $this.attr('data-show-div') + '"]').toggle $this.is(':checked')

    # # Flash radiobuttons, not general
    $('input[name="FLASH"]', 'div.testrun').off('click').on 'click', (e) ->
      $this = $(this)
      $this.siblings('div.image_url').toggle $this.val() == 'CUSTOM'
      $this.parent().find('input[data-param="INIT_DUT"]').val if $this.val() then 'true' else 'false'

    # Start build
    $('#start_jenkins_build').off('click').on 'click', (e) ->
      params = gen_start_params()
      Utils.debug "Start test run with", params
      $.ajax({
        url:      '/jenkins/start'
        type:     'POST'
        data:     params
        dataType: 'json'
        success:  (data, status, jqXHR) ->
          $('.build_response', '.testrun').removeClass('jenkins_error').html "Test run started at <a href=\"#{data.jobUri}\" target=\"_blank\">Jenkins</a>."
        error:    (jqXHR, status, message) ->
          response = $.parseJSON jqXHR.responseText
          $t = $('.build_response', '.testrun').addClass('jenkins_error')
          if response.type == 'http'
            $t.html "Failed to start test run, likely due to networking problems."
          else
            $t.html "Failed to start test run, likely due to incorrect parameters."
      })

    # Apps select all/none
    $('a', '.testrun .appfilters').off('click').on 'click', (e) ->
      e.preventDefault()
      return if $('#tr_apps').prop('disabled')
      select = $(this).hasClass 'select_all'
      $('#tr_apps').select2('destroy').find('option').prop('selected', select).end().select2 width: 'element'

  init = ->
    return if initialized # TODO: how to handle reconnections
    assign_handlers()
    init_form_values()
    reset_apps_list()
    initialized = true

  {
    init:            init,
    reset_apps_list: reset_apps_list,
    assign_handlers: assign_handlers
  }
