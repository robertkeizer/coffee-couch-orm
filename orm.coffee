async	= require "async"
log	= require("logging").from __filename
http	= require "http"
url	= require "url"
util	= require "util"

class Server
	constructor: ( @_url, @db ) ->

	_get_dbs: ( cb ) ->
		# Get a list of databases back.
		@_get @_url + "_all_dbs", ( err, res ) ->
		
	_create_db: ( db, cb ) ->
		# Creates a database..

	_get: ( _url, cb ) ->
		# Just wraps http.get to make it a little easier.
		http.get _url, ( res ) ->
			res.setEncoding "utf8"
			_r = ""
			res.on "error", ( err ) ->
				return cb err
			res.on "data", ( chunk ) ->
				_r += chunk
			res.on "end", ( ) ->
				_k = JSON.parse _r
				if _k.error?
					return cb _k.error
				
				return cb null, _k

	_put: ( _url, data, content_type, cb ) ->
		# Helper for http.request with a PUT type.

		# Parse the given url so that we can generate most of the options object
		o = url.parse _url

		# Fill in other parts of the options object.
		o.method	= "PUT"
		o.headers	= { "Content-Type": content_type }

		# Make the request.
		req = http.request o, ( res ) ->
			res.setEncoding "utf8"
			_r = ""
			res.on "error", ( err ) ->
				return cb err
			res.on "data", ( chunk ) ->
				_r += chunk
			res.on "end", ( ) ->
				_k = JSON.parse _r
				if _k.error?
					return cb _k.error
				return cb null, _k

		# Write the data to the request and end the request.
		req.write data
		req.end( )
			

	doc: ( id, value, cb ) ->
		# Do a little shuffle to allow both
		#  * doc( id, cb )
		#  * doc( id, value, cb )
		if not cb
			cb	= value
			value	= null
	
		# Just do a simple get request for the particular id.
		if not value
			@_get @_url + @db + "/" + id, ( err, res ) ->
				if err
					return cb err
				return cb null, res
		else
			# Value was specified

			# Do a put request to set the document.
			@_put @_url + @db + "/" + id, JSON.stringify( value ), "application/json", ( err, res ) ->
				if err 
					return cb err
				return cb null, res

	view: ( design_name, view, cb ) ->
		# Just a helper to wrap a doc request really.
		@doc "_design/" + design_name + "/_view/" + view, cb

class Base
	_hidden_functions	= [ "constructor", "Server" ]

	@find: ( filter, cb ) ->
		that = @
		@ensure_views ( err ) ->

			if err
				return cb err

			filter_keys = Object.keys filter

			# If no filter was specified return back an error..
			if filter_keys.length is 0
				return cb "Filter required."
			
			# Determine if a valid filter has been specified..
			diff	= [ ]
			_spec	= that.spec( )
			for filter_key in filter_keys
				if _spec[filter_key]?
					diff.push filter_key
			
			# Force a valid filter to have been specified.
			if diff.length is 0
				return cb "Invalid filter"

			# Use the first filter as the index at this point..
			# TODO add multiple filters in the query.. may not be easy without adding
			# more views and such.
			
			# Make the query for the view.
			that::Server.view that.name, "by-" + diff[0], ( err, res ) ->
				if err
					return cb err
				return cb null, res

	@find_one: ( filter, cb ) ->
		# Very similar to @find.. just only returns a single document.
		# Returns an error if the filter matches more than one document.
		@find filter, ( err, res ) ->

			# Error out if we got an error on the find.
			if err
				return cb err

			# Error out if there was more than one result..
			if res.total_rows > 1
				return cb "More than one document found."

			# Return a valid result if the response is simply 1.
			if res.total_rows is 1
				return cb null, res[0]
			
			# Simply return null back if nothing was found.
			if res.total_rows < 1
				return cb null, null

	@generate_views: ( spec, cb ) ->
		# Generate the views for the given spec.
		# Returns an object that usually gets shoved / merged into doc.views
		_r = { }

		# iterate over all the attributes..
		for key, value of spec

			# Define a by-xxx view that is fairly simple.
			view_name = "by-" + key
			_r[view_name] = { "map":	"""
							function( doc ){
								// Make sure we only match the correct documents..
								if( doc._type != "#{@name}" ){
									return
								}
								emit( doc.#{key}, doc );
							}
							""" }
		cb null, _r

	@ensure_views: ( cb ) ->
		# Make a query for the design document. If we can't get that, we know we need to create all the views.
		that = @
		@::Server.doc "_design/" + @name, ( err, doc ) ->
			if err
				# Make all of them..
				_new_doc = { "language": "javascript", "views": { } }

				that.generate_views that.spec( ), ( err, views ) ->
					if err
						return cb err

					# We have views, so shove them into the new design document that we're building.
					_new_doc.views = views
					
					# Shove the document to the server and make sure its committed..
					that::Server.doc "_design/" + that.name, _new_doc, ( err ) ->
						if err
							return cb err
						return cb null
			else
				# Figure out what views we will need to generate ( if any ).

				to_generate	= { }
				existing_views	= Object.keys doc.views
				

				# Iterate over all the keys that should exist..
				for key,value of that.spec( )

					# Right now just check to by-key view.. 
					# in the future consider moving this logic out so that it isn't hardcoded.
					to_check = "by-" + key
					
					# If that view isn't defined in the design doc, include it in to_generate.
					if to_check not in existing_views
						to_generate[key] = value


				# Exit out here if we have all the views we should in the design document already.
				if Object.keys( to_generate ).length is 0
					return cb null

				# Get the views and send the request to update the document..
				that.generate_views to_generate, ( err, views ) =>
					if err
						return cb null

					# Iterate through the response and update the 'doc' object which we grabbed.
					for key, value of views
						if not doc.views[key]?
							doc.views[key] = views[key]
						
					# Make a request to set the document..
					that::Server.doc "_design/" + that.name, doc, ( err ) ->
						if err 
							return cb err
						return cb null

	@spec: ( ) ->
		_return = { }

		# Iterate over the class definition since 
		for key, value of (@) when key.charAt( 0 ) isnt "_" and typeof( @[key] ) isnt 'function'
			_return[key] = @[key]

		for key, value of (@::) when key.charAt( 0 ) isnt "_" and typeof( @::[key] ) isnt 'function' and not key in _hidden_functions
			_return[key] = @::[key]

		log _return
		_return

	@delete: ( ) ->
		

exports.Server	= Server
exports.Base	= Base
