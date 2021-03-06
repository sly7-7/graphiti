module Graphiti
  # Apply filtering logic to the scope
  #
  # If the user requests to filter a field that has not been allowlisted,
  # a +Graphiti::Errors::BadFilter+ error will be raised.
  #
  #   allow_filter :title # :title now allowlisted
  #
  # If the user requests a filter field that has been allowlisted, but
  # does not pass the associated `+:if+ clause, +BadFilter+ will be raised.
  #
  #   allow_filter :title, if: :admin?
  #
  # This will also honor filter aliases.
  #
  #   # GET /posts?filter[headline]=foo will filter on title
  #   allow_filter :title, aliases: [:headline]
  #
  # @see Adapters::Abstract#filter
  # @see Adapters::ActiveRecord#filter
  # @see Resource.allow_filter
  class Scoping::Filter < Scoping::Base
    include Scoping::Filterable

    # Apply the filtering logic.
    #
    # Loop and parse all requested filters, taking into account guards and
    # aliases. If valid, call either the default or custom filtering logic.
    # @return the scope we are chaining/modifying
    def apply
      if missing_required_filters.any?
        raise Errors::RequiredFilter.new(resource, missing_required_filters)
      end

      if missing_dependent_filters.any?
        raise Errors::MissingDependentFilter.new \
          resource, missing_dependent_filters
      end

      each_filter do |filter, operator, value|
        @scope = filter_scope(filter, operator, value)
      end

      @scope
    end

    private

    def filter_scope(filter, operator, value)
      operator = operator.to_s.gsub('!', 'not_').to_sym

      if custom_scope = filter.values[0][:operators][operator]
        custom_scope.call(@scope, value, resource.context)
      else
        filter_via_adapter(filter, operator, value)
      end
    end

    def filter_via_adapter(filter, operator, value)
      type_name = Types.name_for(filter.values.first[:type])
      method    = :"filter_#{type_name}_#{operator}"
      attribute = filter.keys.first

      if resource.adapter.respond_to?(method)
        resource.adapter.send(method, @scope, attribute, value)
      else
        raise Errors::AdapterNotImplemented.new \
          resource.adapter, attribute, method
      end
    end

    def each_filter
      filter_param.each_pair do |param_name, param_value|
        filter = find_filter!(param_name)
        value, operator = normalize_param(filter, param_value)
        value  = parse_string_value(filter.values[0], value) if value.is_a?(String)
        validate_singular(resource, filter, value)
        value = coerce_types(filter.values[0], param_name.to_sym, value)
        validate_allowlist(resource, filter, value)
        validate_denylist(resource, filter, value)
        value = value[0] if filter.values[0][:single]
        yield filter, operator, value
      end
    end

    def coerce_types(filter, name, value)
      type_name = filter[:type]
      is_array = type_name.to_s.starts_with?('array_of') ||
        Types[type_name][:canonical_name] == :array

      if is_array
        @resource.typecast(name, value, :filterable)
      else
        value = value.nil? || value.is_a?(Hash) ? [value] : Array(value)
        value.map { |v| @resource.typecast(name, v, :filterable) }
      end
    end

    def normalize_param(filter, param_value)
      param_value = { eq: param_value } unless param_value.is_a?(Hash)
      value = param_value.values.first
      operator = param_value.keys.first

      if filter.values[0][:type] == :hash
        value, operator = \
          parse_hash_value(filter, param_value, value, operator)
      else
        value = param_value.values.first
      end

      [value, operator]
    end

    def validate_singular(resource, filter, value)
      if filter.values[0][:single] && value.is_a?(Array)
        raise Errors::SingularFilter.new(resource, filter, value)
      end
    end

    def validate_allowlist(resource, filter, values)
      values.each do |v|
        if allow = filter.values[0][:allow]
          unless allow.include?(v)
            raise Errors::InvalidFilterValue.new(resource, filter, v)
          end
        end
      end
    end

    def validate_denylist(resource, filter, values)
      values.each do |v|
        if deny = filter.values[0][:deny]
          if deny.include?(v)
            raise Errors::InvalidFilterValue.new(resource, filter, v)
          end
        end
      end
    end

    def parse_hash_value(filter, param_value, value, operator)
      if operator != :eq
        operator = :eq
        value = param_value
      end

      if value.is_a?(String)
        value = value.gsub('{{{', '{').gsub('}}}', '}')
      end

      [value, operator]
    end

    # foo,bar,baz becomes ["foo", "bar", "baz"] (unless array type)
    # {{foo}} becomes ["foo"]
    # {{foo,bar}},baz becomes ["foo,bar", "baz"]
    #
    # JSON of
    # {{{ "id": 1 }}} becomes { 'id' => 1 }
    def parse_string_value(filter, value)
      type = Graphiti::Types[filter[:type]]
      array_or_string = [:string, :array].include?(type[:canonical_name])
      if (arr = value.scan(/\[.*?\]/)).present? && array_or_string
        value = arr.map do |json|
          begin
            JSON.parse(json)
          rescue
            raise Errors::InvalidJSONArray.new(resource, value)
          end
        end
        value = value[0] if value.length == 1
      else
        value = parse_string_arrays(value)
      end
      value
    end

    def parse_string_arrays(value)
      # Find the quoted strings
      quotes = value.scan(/{{.*?}}/)
      # remove them from the rest
      quotes.each { |q| value.gsub!(q, '') }
      # remove the quote characters from the quoted strings
      quotes.each { |q| q.gsub!('{{', '').gsub!('}}', '') }
      # merge everything back together into an array
      value = Array(value.split(',')) + quotes
      # remove any blanks that are left
      value.reject! { |v| v.length.zero? }
      value = value[0] if value.length == 1
      value
    end
  end
end
