# app.rb

# include current directory in load path
$:.unshift(".").uniq!

require 'sinatra'
require 'sinatra/json'
require 'java'
require 'jbundler'
require 'eventswarm-jar'
require 'log4j-jar'
require 'revs/log4_j_logger'
require 'rule'
require 'rule_processor'
require 'stream'

java_import 'org.apache.kafka.streams.processor.AbstractProcessor'
java_import 'org.apache.kafka.streams.processor.ProcessorSupplier'
java_import 'com.eventswarm.expressions.TrueExpression'

# make sure we can connect from anywhere
set :bind, '0.0.0.0'
set :streams, {}

class Copier < AbstractProcessor  
  def process(key, value)
    context.forward(key,value)
  end
end

class BlockSupplier
  include ProcessorSupplier

  def initialize(&block)
    @creator = block
  end

  def get
    @creator.call
  end
end

def make_stream(params, supplier)
  stream = Stream.new(params[:input], params[:output], supplier)
  stream.start
  settings.streams[stream.id] = stream # save the stream
  stream.to_h
end

def json_params(request)
  body = request.body.read
  body.empty? ? {} : JSON.parse(body)
end

get '/ping' do
  "pong\n"
end

# copy records from input topic to output topic using simple copier
post '/copy' do
  content_type :json
  params.merge!(json_params(request)) # accept params either via JSON or URL

  supplier = BlockSupplier.new do 
    Copier.new
  end
  json(make_stream(params, supplier)) + "\n"
end

post '/true' do
  content_type :json
  params.merge!(json_params(request)) # accept params either via JSON or URL

  
  supplier = BlockSupplier.new do
    expr = TrueExpression.new   # use an always true expression
    rule = Rule.new(expr, expr) # expression is both entry point and match trigger
    RuleProcessor.new(rule)
  end
  json(make_stream(params, supplier)) + "\n"
end

get '/stream/:id' do |id|
  json(settings.streams[id].to_h) + "\n"
end

get '/streams' do 
  json(settings.streams.values.map{|value| value.to_h }) + "\n"
end
  
delete '/stream/:id' do |id|
  settings.streams[id].close
  settings.streams.delete(id)
end
