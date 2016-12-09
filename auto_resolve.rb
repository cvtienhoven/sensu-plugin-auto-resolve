# Resolves a failed check after a specified time.

require 'net/http'
require 'json'
require 'sensu-plugin/utils'

module Sensu
  module Extension
    class AutoResolve < Handler
      def name
        'auto_resolve'
      end

      def description
        'resolves a failed check after a specified time'
      end

      def options
        return @options if @options
        @options = {
          interval: 60
        }
        if @settings
          if @settings['auto_resolve'] && @settings['auto_resolve'].is_a?(Hash)
            @options.merge!(@settings[:auto_resolve])
          end
          if @settings['api'] && @settings['api'].is_a?(Hash)
            @options['api'] = @settings['api']
          end
        end
        @options
      end

      def run(event_data)
        retval = process_event_for_auto_resolve(event_data)
        yield(retval, 0)
      end

      def post_init
        @logger.info('Setting up TTL expiration loop')
        if options['api']
          EM::PeriodicTimer.new(options[:interval]) do
            periodic_auto_resolve_expiration
          end
        else
          @logger.info('No API access, deactivating TTL expiration loop')
        end
      end

      def process_event_for_auto_resolve(event_data)
        @logger.info('auto_resolve process event')
        retval = 'event has no tag auto_resolve_time=X'
        event = JSON.parse(event_data)
        check = event['check']
        tags = check['tags'] unless check.nil?
        new_expiry = get_auto_resolve_time(tags) unless tags.nil?
        unless new_expiry.nil?
          client_name = event['client']['name'] unless event['client'].nil?
          check_name = check['name'] unless check.nil?
          @logger.info("Received event with tag auto_resolve_time: #{client_name}_#{check_name} expires in #{new_expiry} seconds")
          now = Time.now.to_i
          expires_at = now + new_expiry
          res = api_post("/stashes/auto_resolve/#{client_name}_#{check_name}", { auto_resolve: expires_at }.to_json)
          retval = 'stashed auto_resolve for event - code ' + res.code.to_s
        end
        retval
      end

      def get_auto_resolve_time(tags)
        retval = nil
        tags.each { |tag|
          if tag.split('=')[0] == 'auto_resolve_time'
            @logger.debug('auto_resolve_time is set')
            value = tag.split("=")[1]
            if value.match(/^\d+$/)
              retval = value.to_i
              break
            end
            @logger.info('auto_resolve_time is not an integer')
          end
        }
        retval
      end

      def periodic_auto_resolve_expiration
        @logger.info('Starting execution of periodic auto_resolve run')
        all_stashes_s = api_get('/stashes')
        all_stashes = JSON.parse(all_stashes_s.body)
        auto_resolve_stashes = all_stashes.select { |x| x['path'] =~ /\Aauto_resolve\// }
        now = Time.now.to_i
        auto_resolve_stashes.each do |stash|
          check_and_expire_auto_resolve_stash(stash, now)
        end
        @logger.info('Done execution of periodic auto_resolve run')
      end

      def check_and_expire_auto_resolve_stash(stash, now)
        expiry = stash['content']['auto_resolve'].to_i unless stash['content'].nil?
        # #YELLOW
        if !expiry.nil? && expiry <= now # rubocop:disable GuardClause
          client_name, check_name = names_from_path(stash['path'])
          age = (now - expiry).to_s
          @logger.info("auto_resolve - entry for #{client_name}_#{check_name} marked for resolve #{age} seconds ago")
          payload = { client: client_name, check: check_name }
          api_post('/resolve', payload.to_json)
          api_delete("/stashes/#{stash['path']}")
        end
      end

      def api_post(path, payload)
        api_request(Net::HTTP::Post, path, payload)
      end

      def api_delete(path)
        api_request(Net::HTTP::Delete, path, nil)
      end

      def api_get(path)
        api_request(Net::HTTP::Get, path, nil)
      end

      def api_request(method, path, payload)
        http = Net::HTTP.new(options['api']['host'], options['api']['port'])
        req = method.new(path)
        if options['api']['user'] && options['api']['password']
          req.basic_auth(options['api']['user'], options['api']['password'])
        end
        # #YELLOW
        unless payload.nil? # rubocop:disable IfUnlessModifier
          req.body = payload
        end
        http.request(req)
      end

      def logger
        Sensu::Logger.get
      end

      def get_check_data(event_data)
        event = JSON.parse(event_data)
        check = event['check']
        tags = check['tags'] unless check.nil?
        new_expiry = get_auto_resolve_time(tags) unless tags.nil?
        client_name = event['client']['name'] unless event['client'].nil?
        check_name = check['name'] unless check.nil?
        [new_expiry, client_name, check_name]
      end

      def names_from_path(path)
        subpath = path.split('/', 2)[1]
        subpath.split('_', 2)
      end
    end # class AutoResolve
  end # module Extension
end # module Sensu
