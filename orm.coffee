async	= require "async"
log	= require("logging").from __filename
http	= require "http"

class Server
	constructor: ( @url, @db ) ->

	_get_dbs: ( cb ) ->
		# Get a list of databases back.
		@_get @url + "_all_dbs", ( err, res ) ->
		
	_create_db: ( db, cb ) ->
		# Creates a database..

	_get: ( url, cb ) ->
		log url
		# Just wraps http.get to make it a little easier.
		http.get url, ( res ) ->
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

	doc: ( id, value, cb ) ->
		# Do a little shuffle to allow both doc( id, cb ) and doc( id, value, cb )
		if not cb
			cb	= value
			value	= null

		if not value
			@_get @url + @db + "/" + id, ( err, res ) ->
				if err
					return cb err
				return cb null, res
		else
			# Value was specified, so we're setting the document..
			log id
			log value
			return cb "Foo"

class Base
	_hidden_functions = [ "constructor", "Server" ]

	@find_all: ( filter, cb ) ->
		@ensure_views ( err ) ->
			if err
				return cb err

			# At this point make a request based on the filter..
			# Use @::Server.. 

			return cb null

	@generate_views: ( spec, cb ) ->
		# Generate the views for the given spec.
		# Returns an object that usually gets shoved / merged into doc.views
		_r = { }
		for key, value of spec
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
		@::Server.doc "_design/" + @name, ( err, doc ) =>
			if err
				# Make all of them..
				_new_doc = { "language": "javascript", "views": { } }

				@generate_views @spec( ), ( err, views ) =>
					if err
						return cb err

					# We have views, so shove them into the new design document that we're building.
					_new_doc.views = views
					
					# Shove the document to the server and make sure its committed..
					@::Server.doc "_design/" + @name, _new_doc, ( err ) ->
						if err
							return cb err
						return cb null
			else
	
				# Figure out what views we will need to generate ( if any ).
				to_generate	= { }
				existing_views	= Object.keys doc.views

				# Iterate over all the keys that should exist..
				for key, value of @spec( )

					# If the key doesn't exist in the document we just pulled, shove it into to_generate.
					if key not in existing_views
						to_generate[key] = value
		
				# Use to_generate to generate any views that are missing. Then merge into the document..
				#TODO

				# Verify the document to make sure it contains all the correct views.
				return cb null

	@spec: ( ) ->
		_return = { }
		for key, value of (@::) when key not in _hidden_functions
			_return[key] = typeof @::[key]( null, true )
		_return

	@delete: ( ) ->
		

exports.Server	= Server
exports.Base	= Base
