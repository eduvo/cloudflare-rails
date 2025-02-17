require 'net/http'
require 'uri'

module CloudflareRails
  class Importer
    # Exceptions contain the Net::HTTP
    # response object accessible via the {#response} method.
    class ResponseError < StandardError
      # Returns the response of the last request
      # @return [Net::HTTPResponse] A subclass of Net::HTTPResponse, e.g.
      # Net::HTTPOK
      attr_reader :response

      # Instantiate an instance of ResponseError with a Net::HTTPResponse object
      # @param [Net::HTTPResponse]
      def initialize(response)
        @response = response
        super(response)
      end
    end

    BASE_URL = 'https://www.cloudflare.com'.freeze
    IPS_V4_URL = '/ips-v4/'.freeze
    IPS_V6_URL = '/ips-v6/'.freeze

    class << self
      def ips_v6
        fetch IPS_V6_URL
      end

      def ips_v4
        fetch IPS_V4_URL
      end

      def fetch(url)
        proxy_uri = URI.parse(ENV['http_proxy'] ? ENV['http_proxy'] : "")

        if !::Rails.application.config.cloudflare.proxy_server.nil?
          proxy_uri = URI.parse(::Rails.application.config.cloudflare.proxy_server)
        end

        uri = URI("#{BASE_URL}#{url}")

        resp = Net::HTTP.start(uri.host,
                               uri.port,
                               p_addr = proxy_uri.host,
                               p_port = proxy_uri.port,
                               p_user = proxy_uri.user,
                               p_pass = proxy_uri.password,
                               use_ssl: true,
                               read_timeout: Rails.application.config.cloudflare.timeout,
                               open_timeout: ::Rails.application.config.cloudflare.timeout) do |http|
          req = Net::HTTP::Get.new(uri)

          http.request(req)
        end

        raise ResponseError, resp unless resp.is_a?(Net::HTTPSuccess)

        resp.body.split("\n").reject(&:blank?).map { |ip| IPAddr.new ip }
      end

      def fetch_with_cache(type)
        Rails.cache.fetch("cloudflare-rails:#{type}", expires_in: Rails.application.config.cloudflare.expires_in) do
          send type
        end
      end

      def cloudflare_ips(refresh: false)
        @ips = nil if refresh
        @ips ||= (Importer.fetch_with_cache(:ips_v4) + Importer.fetch_with_cache(:ips_v6)).freeze
      rescue StandardError => e
        Rails.logger.error "cloudflare-rails: error fetching ip addresses from Cloudflare (#{e}), falling back to defaults"
        CloudflareRails::FallbackIps::IPS_V4 + CloudflareRails::FallbackIps::IPS_V6
      end
    end
  end
end
