class Provider::DolarApi < Provider
  include ExchangeRateConcept
  extend SslConfigurable

  Error = Class.new(Provider::Error)

  CACHE_DURATION = 5.minutes

  DOLAR_API_BASE_URL = "https://dolarapi.com/v1".freeze
  ARGENTINA_DATOS_BASE_URL = "https://api.argentinadatos.com/v1".freeze

  def initialize
    @cache_prefix = "dolar_api"
  end

  def healthy?
    response = client.get("#{DOLAR_API_BASE_URL}/dolares/oficial")
    data = JSON.parse(response.body)
    data["compra"].present? && data["venta"].present?
  rescue
    false
  end

  def usage
    with_provider_response do
      UsageData.new(
        used: 0,
        limit: 0,
        utilization: 0,
        plan: "Free"
      )
    end
  end

  # ================================
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      validate_ars_pair!(from, to)

      if from == to
        return Rate.new(date: date, from: from, to: to, rate: 1.0)
      end

      cache_key = "exchange_rate_#{from}_#{to}_#{date}"
      if cached_result = get_cached_result(cache_key)
        return cached_result
      end

      rate_value = if date == Date.current
        fetch_current_rate
      else
        fetch_historical_rate(date)
      end

      raise Error, "No exchange rate found for #{from}/#{to} on #{date}" unless rate_value

      # rate_value is the ARS price per 1 USD (e.g., 1050.5)
      final_rate = if from == "USD" && to == "ARS"
        rate_value
      else
        # ARS -> USD
        (1.0 / rate_value).round(8)
      end

      result = Rate.new(date: date, from: from, to: to, rate: final_rate)
      cache_result(cache_key, result)
      result
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      validate_ars_pair!(from, to)
      validate_date_range!(start_date, end_date)

      if from == to
        return (start_date..end_date).map { |d| Rate.new(date: d, from: from, to: to, rate: 1.0) }
      end

      cache_key = "exchange_rates_#{from}_#{to}_#{start_date}_#{end_date}"
      if cached_result = get_cached_result(cache_key)
        return cached_result
      end

      historical_data = fetch_historical_series
      filtered = historical_data.select { |entry| entry[:date] >= start_date && entry[:date] <= end_date }

      rates = filtered.map do |entry|
        rate_value = if from == "USD" && to == "ARS"
          entry[:rate]
        else
          (1.0 / entry[:rate]).round(8)
        end

        Rate.new(date: entry[:date], from: from, to: to, rate: rate_value)
      end

      rates.sort_by!(&:date)
      cache_result(cache_key, rates)
      rates
    end
  end

  private
    def validate_ars_pair!(from, to)
      unless [ from, to ].include?("ARS")
        raise Error, "DolarAPI only supports currency pairs involving ARS. Got #{from}/#{to}"
      end

      unless [ from, to ].all? { |c| [ "ARS", "USD" ].include?(c) }
        raise Error, "DolarAPI only supports USD/ARS pairs. Got #{from}/#{to}"
      end
    end

    def validate_date_range!(start_date, end_date)
      raise Error, "Start date cannot be after end date" if start_date > end_date
    end

    # Fetches current official rate from DolarAPI
    # Returns the midpoint of compra/venta as Float
    def fetch_current_rate
      response = client.get("#{DOLAR_API_BASE_URL}/dolares/oficial")
      data = JSON.parse(response.body)

      compra = data["compra"].to_f
      venta = data["venta"].to_f

      return nil if compra <= 0 || venta <= 0

      ((compra + venta) / 2.0).round(4)
    rescue Faraday::Error, JSON::ParserError => e
      raise Error, "Failed to fetch current rate from DolarAPI: #{e.message}"
    end

    # Fetches a specific historical rate from ArgentinaDatos
    # Returns the midpoint as Float, or nil if not found
    def fetch_historical_rate(date)
      series = fetch_historical_series
      entry = series.find { |e| e[:date] == date }

      # If exact date not found, find closest previous date
      entry ||= series.select { |e| e[:date] <= date }.max_by { |e| e[:date] }

      entry&.dig(:rate)
    end

    # Fetches the full historical series from ArgentinaDatos
    # Returns array of { date: Date, rate: Float }
    def fetch_historical_series
      cache_key = "historical_series"
      if cached = get_cached_result(cache_key)
        return cached
      end

      response = client.get("#{ARGENTINA_DATOS_BASE_URL}/cotizaciones/dolares/oficial")
      data = JSON.parse(response.body)

      series = data.filter_map do |entry|
        date = Date.parse(entry["fecha"])
        compra = entry["compra"].to_f
        venta = entry["venta"].to_f

        next if compra <= 0 || venta <= 0

        { date: date, rate: ((compra + venta) / 2.0).round(4) }
      rescue ArgumentError
        next
      end

      cache_result(cache_key, series)
      series
    rescue Faraday::Error, JSON::ParserError => e
      raise Error, "Failed to fetch historical rates from ArgentinaDatos: #{e.message}"
    end

    # ================================
    #           Caching
    # ================================

    def get_cached_result(key)
      Rails.cache.read("#{@cache_prefix}_#{key}")
    end

    def cache_result(key, data)
      Rails.cache.write("#{@cache_prefix}_#{key}", data, expires_in: CACHE_DURATION)
    end

    # ================================
    #         HTTP Client
    # ================================

    def client
      @client ||= Faraday.new(ssl: self.class.faraday_ssl_options) do |faraday|
        faraday.request(:retry, {
          max: 3,
          interval: 0.5,
          interval_randomness: 0.5,
          backoff_factor: 2,
          retry_statuses: [ 429 ],
          exceptions: [ Faraday::ConnectionFailed, Faraday::TimeoutError ]
        })

        faraday.request :json
        faraday.response :raise_error

        faraday.headers["Accept"] = "application/json"
        faraday.options.timeout = 10
        faraday.options.open_timeout = 5
      end
    end

    def default_error_transformer(error)
      case error
      when Faraday::Error
        Error.new(error.message, details: error.response&.dig(:body))
      when Error
        error
      else
        Error.new(error.message)
      end
    end
end
