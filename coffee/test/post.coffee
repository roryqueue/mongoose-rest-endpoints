express = require 'express'
request = require 'supertest'
should = require 'should'
Q = require 'q'

mongoose = require 'mongoose'

mre = require '../lib/endpoint'
# Custom "Post" and "Comment" documents

commentSchema = new mongoose.Schema
	comment:String
	_post:
		type:mongoose.Schema.Types.ObjectId
		ref:'Post'
	_author:
		type:mongoose.Schema.Types.ObjectId
		ref:'Author'


postSchema = new mongoose.Schema
	date:Date
	number:Number
	string:
		type:String
		required:true
	_comments:[
			type:mongoose.Schema.Types.ObjectId
			ref:'Comment'
			$through:'_post'
	]

authorSchema = new mongoose.Schema
	name:'String'

# Custom middleware for testing
requirePassword = (password) ->
	return (req, res, next) ->
		if req.query.password and req.query.password is password
			next()
		else
			res.send(401)
mongoose.connect('mongodb://localhost/mre_test')

cascade = require 'cascading-relations'


postSchema.plugin(cascade)
commentSchema.plugin(cascade)
authorSchema.plugin(cascade)

mongoose.model('Post', postSchema)
mongoose.model('Comment', commentSchema)
mongoose.model('Author', authorSchema)

mongoose.set 'debug', true



describe 'Post', ->

	describe 'Basic object', ->
		beforeEach (done) ->
			@endpoint = new mre('/api/posts', 'Post')
			@app = express()
			@app.use(express.bodyParser())
			@app.use(express.methodOverride())
			done()
		afterEach (done) ->
			# clear out
			mongoose.connection.collections.posts.drop()
			done()
		it 'should let you post with no hooks', (done) ->

			@endpoint.register(@app)

			data = 
				date:Date.now()
				number:5
				string:'Test'

			request(@app).post('/api/posts/').send(data).end (err, res) ->
				res.status.should.equal(201)
				res.body.number.should.equal(5)
				res.body.string.should.equal('Test')
				done()

		it 'should run middleware', (done) ->
			@endpoint.addMiddleware('post', requirePassword('asdf')).register(@app)
			data = 
				date:Date.now()
				number:5
				string:'Test'

			

			request(@app).post('/api/posts/').query
				password:'asdf'
			.send(data).end (err, res) =>
				res.status.should.equal(201)
				res.body.number.should.equal(5)
				res.body.string.should.equal('Test')

				request(@app).post('/api/posts/').query
					password:'ffff'
				.send(data).end (err, res) =>
					res.status.should.equal(401)
					done()

		it 'should run pre filter', (done) ->
			postData = 
				date:Date.now()
				number:5
				string:'Test'

			@endpoint.tap 'pre_filter', 'post', (req, data, next) ->
				data.number = 7
				return data
			.register(@app)

			request(@app).post('/api/posts/').send(postData).end (err, res) ->
				res.status.should.equal(201)
				res.body.number.should.equal(7)
				res.body.string.should.equal('Test')
				done()

		it 'should run pre response', (done) ->
			postData = 
				date:Date.now()
				number:5
				string:'Test'

			@endpoint.tap 'pre_response', 'post', (req, data, next) ->
				data.number = 7
				return data
			.register(@app)

			request(@app).post('/api/posts/').send(postData).end (err, res) ->
				res.status.should.equal(201)
				res.body.number.should.equal(7)
				res.body.string.should.equal('Test')

				# Make sure it didn't actually update the post
				mongoose.model('Post').findById res.body._id, (err, mod) ->
					mod.number.should.equal(5)
					done()


		
	describe 'Cascading relations', ->
		beforeEach (done) ->
			@endpoint = new mre('/api/posts', 'Post')
			@app = express()
			@app.use(express.bodyParser())
			@app.use(express.methodOverride())
			done()
		afterEach (done) ->
			# clear out
			mongoose.connection.collections.posts.drop()
			done()

		it 'should let you post with relations', (done) ->
			@endpoint.cascade ['_comments'], (data, path) ->
				data.comment += 'FFF'
				return data
			.register(@app)

			data = 
				date:Date.now()
				number:5
				string:'Test'
				_related:
					_comments:[
							comment:'asdf1234'
					]

			request(@app).post('/api/posts/').send(data).end (err, res) ->
				res.status.should.equal(201)
				res.body.number.should.equal(5)
				res.body.string.should.equal('Test')
				res.body._comments.length.should.equal(1)
				res.body._related._comments.length.should.equal(1)
				res.body._related._comments[0].comment.should.equal('asdf1234FFF')
				done()