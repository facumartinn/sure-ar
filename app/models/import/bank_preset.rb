class Import::BankPreset
  PRESETS = {
    "galicia" => {
      name: "Banco Galicia",
      country: "AR",
      col_sep: ",",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Monto",
      name_col_label: "Descripcion"
    },
    "brubank" => {
      name: "Brubank",
      country: "AR",
      col_sep: ",",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Monto",
      name_col_label: "Descripcion"
    },
    "mercadopago" => {
      name: "Mercado Pago",
      country: "AR",
      col_sep: ",",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Monto",
      name_col_label: "Detalle"
    },
    "uala" => {
      name: "Uala",
      country: "AR",
      col_sep: ",",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Monto",
      name_col_label: "Descripcion"
    },
    "macro" => {
      name: "Banco Macro",
      country: "AR",
      col_sep: ",",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Importe",
      name_col_label: "Concepto"
    },
    "santander_ar" => {
      name: "Santander Argentina",
      country: "AR",
      col_sep: ";",
      date_format: "%d/%m/%Y",
      number_format: "1.234,56",
      signage_convention: "inflows_positive",
      amount_type_strategy: "signed_amount",
      date_col_label: "Fecha",
      amount_col_label: "Monto",
      name_col_label: "Descripcion"
    }
  }.freeze

  attr_reader :key, :config

  def initialize(key, config)
    @key = key
    @config = config
  end

  def name
    config[:name]
  end

  def country
    config[:country]
  end

  def template_attributes
    config.slice(
      :col_sep, :date_format, :number_format,
      :signage_convention, :amount_type_strategy,
      :date_col_label, :amount_col_label, :name_col_label
    ).transform_keys(&:to_s)
  end

  class << self
    def all
      PRESETS.map { |key, config| new(key, config) }
    end

    def for_country(country_code)
      all.select { |preset| preset.country == country_code.to_s }
    end

    def find(key)
      config = PRESETS[key.to_s]
      return nil unless config

      new(key.to_s, config)
    end
  end
end
