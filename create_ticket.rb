#!/usr/bin/env ruby

module Otrs
	require 'ostruct'
	require 'mysql2'
	require 'net/http'
	require 'uri'
	require 'json'
	require 'logger'

  DB_HOST = "<OTRS DB_IP>".freeze
  DB_USER = "<OTRS DB_USER>".freeze
  DB_NAME = "<OTRS DB_NAME>".freeze
  DB_PASSWORD = "<OTRS DB_PASSWORD>".freeze
	OTRS_USER = '<OTRS USER>'.freeze
	OTRS_PASS = '<OTRS PASS>'.freeze
	OTRS_REST_URL = '<OTRS REST URL>'.freeze
	OTRS_REST_URI_CREATE_TICKET = '<OTRS REST URI>'.freeze
	IGNORE_PHONES = %w().freeze
	LOG_FILE = '<OTRS LOGFILE>'.freeze

	module Database
	  class Connection
	  	def initialize(agi)
	  		@agi = agi
	  	end

	  	# Search current agent
			def current_owner
				@current_owner ||= OpenStruct.new(find_owner_by_phone(@agi.arg_1))
			end

			# Search current ticket in current time range
			def current_ticket_exists?
				@current_ticket ||= OpenStruct.new(find_ticket_by_phone(@agi.callerid))
				!@current_ticket.id.nil?
			end

			# Search current client
			def current_customer
				@current_customer ||= OpenStruct.new(find_customer_by_phone(@agi.callerid))
			end

	  	private

			# +----+-------+-------------+
			# | id | login | customer_id |
			# +----+-------+-------------+
			# |  1 | test  | RIC         |
			# +----+-------+-------------+
			def find_customer_by_phone(phone)
				query = <<-SQL
					SELECT
						id,
						login,
						customer_id
					FROM
						customer_user
					WHERE
						phone = '#{phone}'
					OR
						mobile = '#{phone}'
					OR
						fax = '#{phone}'
					LIMIT 1
				SQL

				search(query).first
			end

			def find_ticket_by_phone(phone)
				start_date = if (0..6).include?(Time.now.hour)
					(Time.now - 60*60*24).strftime("%F 06:00:00")
				else
					Time.now.strftime("%F 06:00:00")
				end
				end_date = Time.now.strftime("%F %T")

				query = <<-SQL
					SELECT
						id
					FROM
						ticket
					WHERE
						user_id = '#{current_owner.user_id}'
					AND
						title REGEXP '#{phone}$'
					AND (
						create_time
						BETWEEN STR_TO_DATE('#{start_date}', '%Y-%m-%d %H:%i:%s')
						AND STR_TO_DATE('#{end_date}', '%Y-%m-%d %H:%i:%s')
					)
					LIMIT 1
				SQL

				search(query).first
			end

			# +---------+-------+
			# | user_id | login |
			# +---------+-------+
			# |       2 | bra   |
			# +---------+-------+
			def find_owner_by_phone(phone)
				return {} if phone.empty?

				query = <<-SQL
					SELECT
					DISTINCT
						user_id,
						users.login
					FROM
						user_preferences
					INNER JOIN users
					ON users.id = user_preferences.user_id
					WHERE
						preferences_key = 'UserComment'
					AND
						preferences_value = '#{phone}'
					LIMIT 1
				SQL

				search(query).first
			end

			def search(params)
				client.query(params)
			rescue => e
				raise e.message
			end

			def client
				@client ||= Mysql2::Client.new(
					host: DB_HOST,
					username: DB_USER,
					database: DB_NAME,
					password: DB_PASSWORD
				)
			rescue => e
				raise e.message
			end
	  end
	end

	module Rest
		class Connection
			def initialize(connector, params)
				@db_connector = connector
				@params = params
			end

			def create_ticket
				callerid = if @db_connector.current_customer.login
					@db_connector.current_customer.login
				else
					'--'
				end

				title = "Заявка создана по телефону #{@params.callerid}"

				new_ticket = {
					UserLogin: OTRS_USER,
					Password: OTRS_PASS,
					Ticket: {
						Title: title,
						Queue: 'Retail',
						State: :new,
						Priority: '3 normal',
						CustomerUser: callerid,
						CustomerId: @db_connector.current_customer.customer_id,
						OwnerId: @db_connector.current_owner.user_id,
						Owner: @db_connector.current_owner.login
					},
					Article: {
						Subject: title,
						Body: '--',
						ContentType: 'text/plain; charset=utf8'
					}
				}

				create(new_ticket)
			end

			private

			def create(data)
				uri = URI.parse("#{OTRS_REST_URL}#{OTRS_REST_URI_CREATE_TICKET}")
				header = { 'Content-Type' => 'text/json' }
				http = Net::HTTP.new(uri.host, uri.port)
				request = Net::HTTP::Post.new(uri.request_uri, header)
				request.body = data.to_json

				http.request(request).body
			end
		end
	end

	module Asterisk
		module Agi
		  class Initiator
				def initialize(input)
			    @args = []
			    input.each_line do |line|
						break if line.to_s.strip.empty?
						@args << line[4..-1].split(':').map(&:strip)
			    end
				end

				def call
			    @args_struct ||= OpenStruct.new(@args.to_h)
				end
		  end
		end

		class Integrator
			def initialize(stdin)
				@agi_args =	 Agi::Initiator.new(stdin).call
				@db_connector = Database::Connection.new(@agi_args)
				@rest_connector = Rest::Connection.new(@db_connector, @agi_args)

				@logger = Logger.new(LOG_FILE)
			end

			def call
				resp = if params_invalid?
					@db_connector.current_ticket_exists?
				else
					@rest_connector.create_ticket
				end

				@logger.info { "from #{@agi_args.callerid} to #{@agi_args.arg_1}: #{resp}" }
			end

			private

			def params_invalid?
				IGNORE_PHONES.include?(@agi_args.callerid) ||
					!@db_connector.current_owner.user_id ||
					@db_connector.current_ticket_exists?
			end
		end
	end
end

Otrs::Asterisk::Integrator.new(STDIN).call
