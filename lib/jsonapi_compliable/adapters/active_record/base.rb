module JsonapiCompliable
  module Adapters
    module ActiveRecord
      class Base < ::JsonapiCompliable::Adapters::Abstract
        def filter_string_eq(scope, attribute, value, is_not: false)
          column = scope.klass.arel_table[attribute]
          clause = column.lower.eq_any(value.map(&:downcase))
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_string_eql(scope, attribute, value, is_not: false)
          clause = { attribute => value }
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_string_not_eq(scope, attribute, value)
          filter_string_eq(scope, attribute, value, is_not: true)
        end

        def filter_string_not_eql(scope, attribute, value)
          filter_string_eql(scope, attribute, value, is_not: true)
        end

        def filter_string_prefix(scope, attribute, value, is_not: false)
          column = scope.klass.arel_table[attribute]
          map = value.map { |v| "#{v}%" }
          clause = column.lower.matches_any(map)
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_string_not_prefix(scope, attribute, value)
          filter_string_prefix(scope, attribute, value, is_not: true)
        end

        def filter_string_suffix(scope, attribute, value, is_not: false)
          column = scope.klass.arel_table[attribute]
          map = value.map { |v| "%#{v}" }
          clause = column.lower.matches_any(map)
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_string_not_suffix(scope, attribute, value)
          filter_string_suffix(scope, attribute, value, is_not: true)
        end

        def filter_string_like(scope, attribute, value, is_not: false)
          column = scope.klass.arel_table[attribute]
          map = value.map { |v| "%#{v.downcase}%" }
          clause = column.lower.matches_any(map)
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_string_not_like(scope, attribute, value)
          filter_string_like(scope, attribute, value, is_not: true)
        end

        def filter_integer_eq(scope, attribute, value, is_not: false)
          clause = { attribute => value }
          is_not ? scope.where.not(clause) : scope.where(clause)
        end
        alias :filter_float_eq :filter_integer_eq
        alias :filter_decimal_eq :filter_integer_eq
        alias :filter_date_eq :filter_integer_eq
        alias :filter_boolean_eq :filter_integer_eq

        def filter_integer_not_eq(scope, attribute, value)
          filter_integer_eq(scope, attribute, value, is_not: true)
        end
        alias :filter_float_not_eq :filter_integer_not_eq
        alias :filter_decimal_not_eq :filter_integer_not_eq
        alias :filter_date_not_eq :filter_integer_not_eq

        def filter_integer_gt(scope, attribute, value)
          column = scope.klass.arel_table[attribute]
          scope.where(column.gt_any(value))
        end
        alias :filter_float_gt :filter_integer_gt
        alias :filter_decimal_gt :filter_integer_gt
        alias :filter_datetime_gt :filter_integer_gt
        alias :filter_date_gt :filter_integer_gt

        def filter_integer_gte(scope, attribute, value)
          column = scope.klass.arel_table[attribute]
          scope.where(column.gteq_any(value))
        end
        alias :filter_float_gte :filter_integer_gte
        alias :filter_decimal_gte :filter_integer_gte
        alias :filter_datetime_gte :filter_integer_gte
        alias :filter_date_gte :filter_integer_gte

        def filter_integer_lt(scope, attribute, value)
          column = scope.klass.arel_table[attribute]
          scope.where(column.lt_any(value))
        end
        alias :filter_float_lt :filter_integer_lt
        alias :filter_decimal_lt :filter_integer_lt
        alias :filter_datetime_lt :filter_integer_lt
        alias :filter_date_lt :filter_integer_lt

        def filter_integer_lte(scope, attribute, value)
          column = scope.klass.arel_table[attribute]
          scope.where(column.lteq_any(value))
        end
        alias :filter_float_lte :filter_integer_lte
        alias :filter_decimal_lte :filter_integer_lte
        alias :filter_date_lte :filter_integer_lte

        # Ensure fractional seconds don't matter
        def filter_datetime_eq(scope, attribute, value, is_not: false)
          ranges = value.map { |v| (v..v+1.second-0.00000001) }
          clause = { attribute => ranges }
          is_not ? scope.where.not(clause) : scope.where(clause)
        end

        def filter_datetime_not_eq(scope, attribute, value)
          filter_datetime_eq(scope, attribute, value, is_not: true)
        end

        def filter_datetime_lte(scope, attribute, value)
          value = value.map { |v| v + 1.second-0.00000001 }
          column = scope.klass.arel_table[attribute]
          scope.where(column.lteq_any(value))
        end

        def base_scope(model)
          model.all
        end

        # (see Adapters::Abstract#order)
        def order(scope, attribute, direction)
          scope.order(attribute => direction)
        end

        # (see Adapters::Abstract#paginate)
        def paginate(scope, current_page, per_page)
          scope.page(current_page).per(per_page)
        end

        # (see Adapters::Abstract#count)
        def count(scope, attr)
          if attr.to_sym == :total
            scope.distinct.count
          else
            scope.distinct.count(attr)
          end
        end

        # (see Adapters::Abstract#average)
        def average(scope, attr)
          scope.average(attr).to_f
        end

        # (see Adapters::Abstract#sum)
        def sum(scope, attr)
          scope.sum(attr)
        end

        # (see Adapters::Abstract#maximum)
        def maximum(scope, attr)
          scope.maximum(attr)
        end

        # (see Adapters::Abstract#minimum)
        def minimum(scope, attr)
          scope.minimum(attr)
        end

        # (see Adapters::Abstract#resolve)
        def resolve(scope)
          scope.to_a
        end

        # Run this write request within an ActiveRecord transaction
        # @param [Class] model_class The ActiveRecord class we are saving
        # @return Result of yield
        # @see Adapters::Abstract#transaction
        def transaction(model_class)
          model_class.transaction do
            yield
          end
        end

        def sideloading_classes
          {
            has_many: HasManySideload,
            has_one: HasOneSideload,
            belongs_to: BelongsToSideload,
            many_to_many: ManyToManySideload
          }
        end

        def associate_all(parent, children, association_name, association_type)
          association = parent.association(association_name)
          association.loaded!

          children.each do |child|
            if association_type == :many_to_many &&
                !parent.send(association_name).exists?(child.id) &&
                [:create, :update].include?(JsonapiCompliable.context[:namespace])
              parent.send(association_name) << child
            else
              target = association.instance_variable_get(:@target)
              target |= [child]
              association.instance_variable_set(:@target, target)
            end
          end
        end

        def associate(parent, child, association_name, association_type)
          association = parent.association(association_name)
          association.loaded!
          association.instance_variable_set(:@target, child)
        end

        # When a has_and_belongs_to_many relationship, we don't have a foreign
        # key that can be null'd. Instead, go through the ActiveRecord API.
        # @see Adapters::Abstract#disassociate
        def disassociate(parent, child, association_name, association_type)
          if association_type == :many_to_many
            parent.send(association_name).delete(child)
          else
            # Nothing to do here, happened when we merged foreign key
          end
        end

        # (see Adapters::Abstract#create)
        def create(model_class, create_params)
          instance = model_class.new(create_params)
          instance.save
          instance
        end

        # (see Adapters::Abstract#update)
        def update(model_class, update_params)
          instance = model_class.find(update_params.delete(:id))
          instance.update_attributes(update_params)
          instance
        end

        # (see Adapters::Abstract#destroy)
        def destroy(model_class, id)
          instance = model_class.find(id)
          instance.destroy
          instance
        end
      end
    end
  end
end