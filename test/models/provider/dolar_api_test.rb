require "test_helper"

class Provider::DolarApiTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::DolarApi.new
  end

  # ================================
  #        Health Check Tests
  # ================================

  test "healthy? returns true when API is working" do
    mock_response = mock
    mock_response.stubs(:body).returns('{"compra":1050.0,"venta":1070.0}')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).returns(mock_response)

    assert @provider.healthy?
  end

  test "healthy? returns false when API fails" do
    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).raises(Faraday::Error.new("Connection failed"))

    assert_not @provider.healthy?
  end

  test "healthy? returns false when response is missing data" do
    mock_response = mock
    mock_response.stubs(:body).returns('{}')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).returns(mock_response)

    assert_not @provider.healthy?
  end

  # ================================
  #      Exchange Rate Tests
  # ================================

  test "fetch_exchange_rate returns 1.0 for same currency" do
    date = Date.current
    response = @provider.fetch_exchange_rate(from: "ARS", to: "ARS", date: date)

    assert response.success?
    rate = response.data
    assert_equal 1.0, rate.rate
    assert_equal "ARS", rate.from
    assert_equal "ARS", rate.to
    assert_equal date, rate.date
  end

  test "fetch_exchange_rate for USD to ARS returns correct rate" do
    date = Date.current
    mock_response = mock
    mock_response.stubs(:body).returns('{"compra":1050.0,"venta":1070.0}')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).with("#{Provider::DolarApi::DOLAR_API_BASE_URL}/dolares/oficial").returns(mock_response)

    response = @provider.fetch_exchange_rate(from: "USD", to: "ARS", date: date)

    assert response.success?
    rate = response.data
    assert_equal "USD", rate.from
    assert_equal "ARS", rate.to
    assert_equal 1060.0, rate.rate # (1050 + 1070) / 2
  end

  test "fetch_exchange_rate for ARS to USD returns inverse rate" do
    date = Date.current
    mock_response = mock
    mock_response.stubs(:body).returns('{"compra":1050.0,"venta":1070.0}')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).with("#{Provider::DolarApi::DOLAR_API_BASE_URL}/dolares/oficial").returns(mock_response)

    response = @provider.fetch_exchange_rate(from: "ARS", to: "USD", date: date)

    assert response.success?
    rate = response.data
    assert_equal "ARS", rate.from
    assert_equal "USD", rate.to
    expected_rate = (1.0 / 1060.0).round(8)
    assert_equal expected_rate, rate.rate
  end

  test "fetch_exchange_rate rejects non-ARS pairs" do
    response = @provider.fetch_exchange_rate(from: "USD", to: "EUR", date: Date.current)

    assert_not response.success?
    assert_instance_of Provider::DolarApi::Error, response.error
    assert_match(/ARS/, response.error.message)
  end

  test "fetch_exchange_rate rejects ARS pairs with non-USD currencies" do
    response = @provider.fetch_exchange_rate(from: "ARS", to: "EUR", date: Date.current)

    assert_not response.success?
    assert_instance_of Provider::DolarApi::Error, response.error
    assert_match(/USD\/ARS/, response.error.message)
  end

  test "fetch_exchange_rate uses historical data for past dates" do
    date = Date.parse("2024-06-15")
    mock_response = mock
    mock_response.stubs(:body).returns('[{"fecha":"2024-06-15","compra":900.0,"venta":940.0},{"fecha":"2024-06-14","compra":895.0,"venta":935.0}]')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).with("#{Provider::DolarApi::ARGENTINA_DATOS_BASE_URL}/cotizaciones/dolares/oficial").returns(mock_response)

    response = @provider.fetch_exchange_rate(from: "USD", to: "ARS", date: date)

    assert response.success?
    rate = response.data
    assert_equal 920.0, rate.rate # (900 + 940) / 2
  end

  # ================================
  #    Exchange Rates Range Tests
  # ================================

  test "fetch_exchange_rates returns rates for date range" do
    start_date = Date.parse("2024-06-14")
    end_date = Date.parse("2024-06-15")

    mock_response = mock
    mock_response.stubs(:body).returns('[{"fecha":"2024-06-14","compra":895.0,"venta":935.0},{"fecha":"2024-06-15","compra":900.0,"venta":940.0},{"fecha":"2024-06-16","compra":905.0,"venta":945.0}]')

    @provider.stubs(:client).returns(mock_client = mock)
    mock_client.stubs(:get).with("#{Provider::DolarApi::ARGENTINA_DATOS_BASE_URL}/cotizaciones/dolares/oficial").returns(mock_response)

    response = @provider.fetch_exchange_rates(from: "USD", to: "ARS", start_date: start_date, end_date: end_date)

    assert response.success?
    rates = response.data
    assert_equal 2, rates.length
    assert_equal start_date, rates.first.date
    assert_equal end_date, rates.last.date
  end

  test "fetch_exchange_rates validates date range" do
    response = @provider.fetch_exchange_rates(from: "USD", to: "ARS", start_date: Date.current, end_date: Date.current - 1.day)

    assert_not response.success?
    assert_instance_of Provider::DolarApi::Error, response.error
  end

  test "fetch_exchange_rates rejects non-ARS pairs" do
    response = @provider.fetch_exchange_rates(from: "USD", to: "EUR", start_date: Date.current - 7.days, end_date: Date.current)

    assert_not response.success?
    assert_instance_of Provider::DolarApi::Error, response.error
  end

  test "fetch_exchange_rates returns same currency rates" do
    start_date = Date.parse("2024-06-14")
    end_date = Date.parse("2024-06-16")

    response = @provider.fetch_exchange_rates(from: "ARS", to: "ARS", start_date: start_date, end_date: end_date)

    assert response.success?
    rates = response.data
    assert_equal 3, rates.length
    assert rates.all? { |r| r.rate == 1.0 }
  end

  # ================================
  #       Error Handling Tests
  # ================================

  test "handles Faraday errors gracefully" do
    faraday_error = Faraday::ConnectionFailed.new("Connection failed")

    result = @provider.send(:with_provider_response) { raise faraday_error }

    assert_not result.success?
    assert_instance_of Provider::DolarApi::Error, result.error
  end

  # ================================
  #         Caching Tests
  # ================================

  test "caching stores and retrieves results" do
    @provider.send(:cache_result, "test_key", "test_value")
    assert_equal "test_value", @provider.send(:get_cached_result, "test_key")
  end

  test "cache returns nil for missing keys" do
    assert_nil @provider.send(:get_cached_result, "nonexistent_key")
  end
end
