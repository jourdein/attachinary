(($) ->

  $.attachinary =
    index: 0
    config:
      disableWith: 'Uploading...'
      indicateProgress: true
      invalidFormatMessage: 'Invalid file format'
      template: """
        <ul>
          <% for(var i=0; i<files.length; i++){ %>
            <li>
              <% if(files[i].resource_type == "raw") { %>
                <div class="raw-file"></div>
              <% } else if (files[i].format == "mp3") { %>
                <audio src="<%= $.cloudinary.url(files[i].public_id, { "version": files[i].version, "resource_type": 'video', "format": 'mp3'}) %>" controls />
              <% } else { %>
                <img
                  src="<%= $.cloudinary.url(files[i].public_id, { "version": files[i].version, "format": 'jpg', "crop": 'fill', "width": 75, "height": 75 }) %>"
                  alt="" width="75" height="75" />
              <% } %>
              <a href="#" data-remove="<%= files[i].public_id %>">Remove</a>
            </li>
          <% } %>
        </ul>
      """
      render: (files) ->
        $.attachinary.Templating.template(@template, files: files)
      uploadConfig:
        previewMaxWidth: 100
        previewMaxHeight: 100
        previewCrop: true
        # autoUpload: false       # default is true


  $.fn.attachinary = (options) ->
    settings = $.extend {}, $.attachinary.config, options

    this.each ->
      $this = $(this)

      if !$this.data('attachinary-bond')
        $this.data 'attachinary-bond', new $.attachinary.Attachinary($this, settings)



  class $.attachinary.Attachinary
    constructor: (@$input, @config) ->
      @options = @$input.data('attachinary')
      
      if @config.filesContainerSelector?
        _filesContainer = @config.filesContainerSelector
        @config.filesContainerSelector = if _.isFunction(_filesContainer) then _filesContainer else -> $(_filesContainer)

      _dropZone = @config.dropZone
      @config.dropZone = if _.isFunction(_dropZone) then => _dropZone(@$input) else -> _dropZone

      @files = @options.files

      @$form = @$input.closest('form')
      @$submit = @$form.find(@config.submitSelector ? 'input[type=submit]')
      @$wrapper = @$input.closest(@config.wrapperContainerSelector) if @config.wrapperContainerSelector?

      # infer operation form the received
      # data files. operation is updating if 
      # initially the @files.length > 0 and has `id` val.
      @inferOperation()

      @initFileUpload()
      @addFilesContainer()
      @bindEventHandlers()
      @redraw()
      @checkMaximum()

    initFileUpload: ->
      @options.field_name = @$input.attr('name')

      options =
        dataType: 'json'
        paramName: 'file'
        headers: {"X-Requested-With": "XMLHttpRequest"}
        sequentialUploads: true
        dropZone: @config.dropZone() || @$input

      $.extend options, @config.uploadConfig

      if @$input.attr('accept')
        options.acceptFileTypes = new RegExp("^#{@$input.attr('accept').split(",").join("|")}$", "i")

      @$input.fileupload(options)

    inferOperation: ->
      if @files.length > 0
        # test for the any element (i take the first one)
        # for existence of `id` key
        if @files[0].id?
          @config.method = 'UPDATE'
      return

    bindEventHandlers: ->
      self = this
      @$input.on 'click', (event, data) ->
        if self.isUpdateOperation()
          self.oldFile = self.files[0]
        self.$input.trigger 'attachinary:fileselection'

      @$input.bind 'fileuploadsend', (event, data) =>
        @$input.addClass 'uploading'
        @$wrapper.addClass 'uploading' if @$wrapper?
        @$form.addClass  'uploading'

        @$input.prop 'disabled', true
        if @config.disableWith
          @$submit.each (index,input) =>
            $input = $(input)
            $input.data 'old-val', $input.val() unless $input.data('old-val')?
          @$submit.val  @config.disableWith
          @$submit.prop 'disabled', true

        !@maximumReached()


      @$input.bind 'fileuploaddone', (event, data) =>
        @addFile(data.result)


      @$input.bind 'fileuploadstart', (event) =>
        # important! changed on every file upload
        @$input = $(event.target)


      @$input.bind 'fileuploadalways', (event) =>
        @$input.removeClass 'uploading'
        @$wrapper.removeClass 'uploading' if @$wrapper?
        @$form.removeClass  'uploading'

        @checkMaximum()
        if @config.disableWith
          @$submit.each (index,input) =>
            $input = $(input)
            $input.val  $input.data('old-val')
          @$submit.prop 'disabled', false


      @$input.bind 'fileuploadprogressall', (e, data) =>
        progress = parseInt(data.loaded / data.total * 100, 10)
        @$input.trigger 'attachinary:uploadprogress', [progress]
        if @config.disableWith && @config.indicateProgress
          @$submit.val "[#{progress}%] #{@config.disableWith}"


    addFile: (file) ->
      if !@options.accept || $.inArray(file.format, @options.accept) != -1  || $.inArray(file.resource_type, @options.accept) != -1 || $.inArray("raw", @options.accept) != -1
        
        # only for update operate.
        # replace @files with single length array.
        # specifically, update only on array of length 1.
        if @isUpdateOperation()
          file = $.extend {}, @oldFile, file
          @files = [file]
          @redraw()
          @checkMaximum()
          @$input.trigger 'attachinary:fileupdated', [file]
        else
          @files.push file
          @redraw()
          @checkMaximum()
          @$input.trigger 'attachinary:fileadded', [file]
      else
        alert @config.invalidFormatMessage

    removeFile: (fileIdToRemove) ->
      _files = []
      removedFile = null
      for file in @files
        if file.public_id == fileIdToRemove
          removedFile = file
        else
          _files.push file
      @files = _files
      @redraw()
      @checkMaximum()

      # do removal from cloudinary server if delete token exist
      $.cloudinary.delete_by_token(removedFile.delete_token) if removedFile.delete_token?
      
      @$input.trigger 'attachinary:fileremoved', [removedFile]

    checkMaximum: ->
      if @maximumReached()
        @$wrapper.addClass 'disabled' if @$wrapper?
        @$input.prop('disabled', true)
      else
        @$wrapper.removeClass 'disabled' if @$wrapper?
        @$input.prop('disabled', false)

      if @files.length > 0
        @$input.prop('required', false)
      else if @$input.hasClass('required') 
        @$input.prop('required', true)

    maximumReached: ->
      @options.maximum && @files.length >= @options.maximum && not @isUpdateOperation()

    # update operation is characterized by 
    # 1. config.method == 'update'
    # 2. the maximum == 1
    # 3. only can happend if @files still have files. to get the `id`
    # multiple file will be hard to merge them.
    isUpdateOperation: ->
      if @config.method?
        # this checks on the configuration
        if @config.method.toLowerCase() is 'update' and @options.maximum is 1
          # this check on the current datastore
          
          # can't continue update op since the 
          # datasource is empty and hasn't been preserved yet
          if @oldFile? 
            return no if @oldFile.length == 0 and @files.length == 0
          else if @files.length == 0
            return no

          # old value has been preserveed. (no need to condition)
          return yes
      no

    addFilesContainer: ->
      if @config.filesContainerSelector?
        @$filesContainer = @config.filesContainerSelector(@$input)
      
      unless @config.filesContainerSelector? and @$filesContainer.length > 0
        @$filesContainer = $('<div class="attachinary_container">')
        @$input.after @$filesContainer



    redraw: ->
      that = @
      @$filesContainer.empty()

      if @files.length > 0
        @$filesContainer.append @makeHiddenField(JSON.stringify(@files))

        @$filesContainer.append @config.render(@files)

        @$filesContainer.find('[data-remove]').on 'click.attachinary', (event) ->
          event.preventDefault()
          that.removeFile $(this).data('remove')

        # find the remove button and hide it
        # when in update operation since delete
        # and trying to update record will be trickier
        if @isUpdateOperation()
          @$filesContainer.find('[data-remove]').hide()

        @$filesContainer.show()
      else
        @$filesContainer.append @makeHiddenField(null)
        @$filesContainer.hide()

    makeHiddenField: (value) ->
      $input = $('<input type="hidden">')
      $input.attr 'name', @options.field_name
      $input.val value
      $input




  # JavaScript templating by John Resig's
  $.attachinary.Templating =
    settings:
      start:        '<%'
      end:          '%>'
      interpolate:  /<%=(.+?)%>/g

    escapeRegExp: (string) ->
      string.replace(/([.*+?^${}()|[\]\/\\])/g, '\\$1')

    template: (str, data) ->
      c = @settings
      endMatch = new RegExp("'(?=[^"+c.end.substr(0, 1)+"]*"+@escapeRegExp(c.end)+")","g")
      fn = new Function 'obj',
        'var p=[],print=function(){p.push.apply(p,arguments);};' +
        'with(obj||{}){p.push(\'' +
        str.replace(/\r/g, '\\r')
           .replace(/\n/g, '\\n')
           .replace(/\t/g, '\\t')
           .replace(endMatch,"✄")
           .split("'").join("\\'")
           .split("✄").join("'")
           .replace(c.interpolate, "',$1,'")
           .split(c.start).join("');")
           .split(c.end).join("p.push('") +
           "');}return p.join('');"
      if data then fn(data) else fn

)(jQuery)
