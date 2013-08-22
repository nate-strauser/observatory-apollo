# stub for testing, if we are in the test env Meteor won't be defined
###
if not Meteor? and require?
  {Meteor, EJSON} = require './unit-tests/MeteorStubs.coffee'
  Observatory = Observatory or= {logger: -> console.log "Observatory.logger called"}
  __meteor_bootstrap__ = Meteor.__meteor_bootstrap__
###

#(exports ? this).TLog = TLog
# Class that handles all the logging logic
#
# @example Getting a logger that will print only WARNING and more severe messages both to db and console:
#     TL = TLog.getLogger(TLog.LOGLEVEL_WARNING, true)
#
class TLog
  @_connectLogsBuffer = []
  @_log_http = true

  @addToLogsBuffer: (obj)->
    @_connectLogsBuffer.push obj

  @checkConnectLogsBuffer: ->
    if TLog._connectLogsBuffer.length > 0
      tl = TLog.getLogger()
      for l in TLog._connectLogsBuffer
        msg = "#{l.method} #{l.url}: #{l.status} in #{l.responseTime} ms\n#{l.userAgent}\n#{l.responseHeader}"
        fullMsg = msg + "\nreferrer: #{l.referrer?}"
        loglevel = TLog.LOGLEVEL_VERBOSE
        if l.status >= 500 then loglevel = TLog.LOGLEVEL_FATAL
        else if l.status >= 400 then loglevel = TLog.LOGLEVEL_ERROR
        else if l.status >= 300 then loglevel = TLog.LOGLEVEL_WARNING

        options =
          isServer: true
          message: msg
          full_message: fullMsg
          module: "HTTP"
          timestamp: l.timestamp
          ip: l.forwardedFor #l.remoteAddress
          elapsedTime: l.responseTime # e.g., response time for http or method running time for profiling functions

        # recording the result
        tl._lowLevelLog loglevel, options, l

      TLog._connectLogsBuffer = []


  @_instance = undefined
  @_global_logs = new Meteor.Collection '_observatory_logs'

  # Get a logger with options
  #
  # @param [TLog enum] loglevel desired loglevel, one of TLog.LOGLEVEL_FATAL,TLog.LOGLEVEL_ERROR,TLog.LOGLEVEL_WARNING,TLog.LOGLEVEL_INFO,TLog.LOGLEVEL_VERBOSE
  # @param [Bool] want_to_print if true, log messages will be printed to the console as well
  #
  @getLogger:->
    @_instance?=new TLog TLog.LOGLEVEL_DEBUG, false, true, false
    @_instance

  @LOGLEVEL_FATAL = 0
  @LOGLEVEL_ERROR = 1
  @LOGLEVEL_WARNING = 2
  @LOGLEVEL_INFO = 3
  @LOGLEVEL_VERBOSE = 4
  @LOGLEVEL_DEBUG = 5
  @LOGLEVEL_MAX = 6

  @limit = 300

  @LOGLEVEL_NAMES = [
    "FATAL", "ERROR", "WARNING", "INFO", "VERBOSE", "DEBUG", "MAX"
  ]
  @LOGLEVEL_NAMES_SHORT = [
    "FTL", "ERR", "WRN", "INF", "VRB", "DBG","MAX"
  ]

  constructor: (@_currentLogLevel, @_printToConsole, @_log_user = true, show_warning = true)->
    if TLog._instance? then throw new Error "Attempted to create another instance of the TLog"

    @_logs = TLog._global_logs

    @warn("You should use TLog.getLogger(loglevel, want_to_print) method instead of a constructor! Constructor calls may be removed
      in the next versions of the package.") if show_warning
    @verbose "Creating logger with level #{TLog.LOGLEVEL_NAMES[@_currentLogLevel]}, print to console: #{@_printToConsole}, log user: #{@_log_user}", "Observatory"


  # Set options for a logger
  #
  # @param [TLog enum] loglevel desired (see getLogger())
  # @param [Bool] whether to print to the console
  #
  setOptions: (loglevel, want_to_print = true, log_user = true, log_http = true) ->
    if (loglevel>=0) and (loglevel<=TLog.LOGLEVEL_MAX)
      @_currentLogLevel = loglevel
    @_printToConsole = want_to_print
    @_log_user = log_user
    TLog._log_http = log_http
    @verbose "Setting log options with level #{TLog.LOGLEVEL_NAMES[@_currentLogLevel]}, print to console: #{@_printToConsole}, log user: #{@_log_user}, http logging: #{TLog._log_http}", "Observatory"

  # Main logging methods:
  fatal: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_FATAL,module)

  error: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_ERROR, module)

  warn: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_WARNING, module)

  info: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_INFO, module)

  verbose: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_VERBOSE, module)

  debug: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_DEBUG, module)

  insaneVerbose: (msg, module)->
    @_log(msg,TLog.LOGLEVEL_MAX, module)

  # takes a error and logs it with message and stack trace if available
  trace: (error, message, module)->
    m = "Error: "
    if error.message
      m = m + error.message
    if error.trace
      m = m + " StackTrace: " + error.stack
    if error.reason?
      m = m + " Code: " + error.error + " Reason: " + error.reason
    msg = message + " | " + m if message
    @_log(msg,TLog.LOGLEVEL_ERROR, module)

  # inspects an object, stringifies it and prints out
  dir: (obj, message, module)->
    msg = if message then message else "Inspecting object:"
    if obj?
      mnames = Inspect.methods(obj)
      pnames = Inspect.properties(obj)
      methods = []
      props = []
      for m in mnames
        methods.push m
      for p in pnames
        props.push
          name: p
          value: obj[p]
      @debug(msg, module)
      @_log("Methods: " + EJSON.stringify(methods),TLog.LOGLEVEL_DEBUG, module)
      @_log("Properties: " + EJSON.stringify(props),TLog.LOGLEVEL_DEBUG, module)

  currentLogLevelName: ->
    TLog.LOGLEVEL_NAMES[@_currentLogLevel]

  logCount: ->
    @_logs.find({}).count()


  # low level full logging convenience
  # DOES NOT check current level to allow logging monitoring etc functions
  _lowLevelLog: (loglevel, options, customOptions, fn)->
    #return if loglevel >= @_currentLogLevel

    ts = if options.timestamp_text then options.timestamp_text else @_ps(TLog._convertDate(options.timestamp)) + @_ps(TLog._convertTime(options.timestamp))

    obj =
      isServer: options.isServer or false
      message: options.message
      full_message: options.full_message
      module: options.module
      loglevel: loglevel
      timestamp_text: ts
      timestamp: options.timestamp
      uid: options.uid # user id or null
      ip: options.ip # IP address or null
      elapsedTime: options.elapsedTime # e.g., response time for http or method running time for profiling functions
      customOptions: customOptions # anything else EJSONable that you want to store

    if fn
      @_logs.insert obj, fn # calling this with callback is only useful for testing
    else 
      #console.dir @_logs
      #console.dir obj
      try
        @_logs.insert obj
        #console.dir obj
      catch e
        console.log "ERROR while inserting logs from TLog"
        console.dir e.stack
      
      

  # helper method to format a message from standard API methods
  
  # helper method to get userId
  # TODO: think how to get to it if we are in publish()
  # TODO: Needs testing!
  _checkUser: ->
    user = ''
    try
      uid = if this.userId? then this.userId else Meteor.userId()
      u = Meteor.users.findOne(uid) # TODO: check how it affects performance!
      if u and u.username
        user = u.username
      else
        if u and u.emails and u.emails[0]
          user = u.emails[0].address
        else
          user = uid
    catch err
    {user: user, uid: uid}

  # prepare options object for logging
  _prepareLogOptions: (msg, loglevel, module)->
    srv = Meteor.isServer
    {user, uid} = @_checkUser() if @_log_user
    options =
        isServer: srv
        message: msg
        module: module
        timestamp: new Date
        uid: uid
        user: user
        loglevel: loglevel
    options

  # format message for logging based on the options object
  # TODO: add colorization for HTML or ANSI
  _formatLogMessage: (o, colorize = false)->
    ts = @_ps(TLog._convertDate(o.timestamp)) + @_ps(TLog._convertTime(o.timestamp))
    full_message = ts + if o.isServer then "[SERVER]" else "[CLIENT]"
    full_message+= if o.module then @_ps o.module else "[]"
    full_message+= @_ps(TLog.LOGLEVEL_NAMES[o.loglevel]) #TODO: RANGE CHECK!!!
    full_message+= "[#{o.user}]"
    full_message+= " #{o.message}"
    full_message

  # normal Meteor logging
  # NOTE! --> killing timestamp text storage, formatting should be done during the presentation time
  _log: (msg, loglevel = TLog.LOGLEVEL_INFO, mdl) ->
    if loglevel <= @_currentLogLevel
      options = @_prepareLogOptions msg, loglevel, mdl
      options.full_message = @_formatLogMessage options
      @_lowLevelLog loglevel, options
      console.log(options.full_message) if @_printToConsole

  _convertTimestamp: (timestamp)->
    st = timestamp.getUTCDate() + '/' + timestamp.getUTCMonth() + '/'+timestamp.getUTCFullYear() + ' ' +
      timestamp.getUTCHours()+ ':' + timestamp.getUTCMinutes() + ':' + timestamp.getUTCSeconds() + '.' + timestamp.getUTCMilliseconds()

  @_convertDate: (timestamp)->
    st = timestamp.getUTCDate() + '/' + timestamp.getUTCMonth() + '/'+timestamp.getUTCFullYear()

  @_convertTime: (timestamp, ms=true)->
    ts = timestamp.getUTCHours()+ ':' + timestamp.getUTCMinutes() + ':' + timestamp.getUTCSeconds()
    ts += '.' + timestamp.getUTCMilliseconds() if ms
    ts

  _ps: (s)->
    '['+s+']'

  @_getLogs: (sort)->
    if sort
      @_global_logs.find({}, sort: sort)
    else
      @_global_logs.find {}, sort: {timestamp: -1}

  #Ouch! This should be really protected once auth is figured out.
  @_clear: ->
    @_global_logs.remove {}


# Starting the cycle of watching http logs buffer
if Meteor.isServer
  Meteor.startup ->
    Meteor.setInterval ->
      TLog.checkConnectLogsBuffer()
    , 5000

Inspect =
  TYPE_FUNCTION: "function"

  # Returns an array of (the names of) all methods
  methods: (obj) ->
    testObj = obj or self
    methods = []
    for prop of testObj
      methods.push prop  if typeof testObj[prop] is Inspect.TYPE_FUNCTION and typeof Inspect[prop] isnt Inspect.TYPE_FUNCTION
    methods


  # Returns an array of (the names of) all properties
  properties: (obj) ->
    testObj = obj or self
    properties = []
    for prop of testObj
      properties.push prop  if typeof testObj[prop] isnt Inspect.TYPE_FUNCTION and typeof Inspect[prop] isnt Inspect.TYPE_FUNCTION
    properties

module?.exports?.TLog = TLog
(exports ? this).TLog = TLog
(exports ? this).Inspect = Inspect