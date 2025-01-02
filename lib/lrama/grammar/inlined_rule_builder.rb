# frozen_string_literal: true

module Lrama
  class Grammar
    class InlinedRuleBuilder
      def initialize(rule_counter, midrule_action_counter, parameterizing_rule_resolver, lhs, lhs_tag, rhs, user_code, precedence_sym, line)
        @rule_counter = rule_counter
        @midrule_action_counter = midrule_action_counter
        @parameterizing_rule_resolver = parameterizing_rule_resolver
        @lhs = lhs
        @lhs_tag = lhs_tag
        @rhs = rhs
        @user_code = user_code
        @precedence_sym = precedence_sym
        @line = line
      end

      def build_builders(rule, token, index)
        binding = create_binding(rule, token)

        rule.rhs_list.map do |rhs|
          rule_builder = initialize_builder
          resolve_rhs(rule_builder, rhs, index, binding)
          finalize_builder(rule_builder, rhs, index)
          rule_builder
        end
      end

      private

      def initialize_builder
        RuleBuilder.new(
          @rule_counter,
          @midrule_action_counter,
          @parameterizing_rule_resolver,
          lhs_tag: @lhs_tag
        )
      end

      def create_binding(rule, token)
        return unless token.is_a?(Lexer::Token::InstantiateRule)

        Binding.new(rule, token.args)
      end

      def resolve_rhs(rule_builder, rhs, index, bindings)
        @rhs.each_with_index do |token, i|
          if index == i
            rhs.symbols.each { |sym| rule_builder.add_rhs(bindings.nil? ? sym : bindings.resolve_symbol(sym)) }
          else
            rule_builder.add_rhs(token)
          end
        end
      end

      def finalize_builder(rule_builder, rhs, index)
        rule_builder.lhs = @lhs
        rule_builder.line = @line
        rule_builder.precedence_sym = @precedence_sym
        rule_builder.user_code = replace_user_code(rhs, index)
      end

      def replace_user_code(inline_rhs, index)
        return @user_code if inline_rhs.user_code.nil?
        return @user_code if @user_code.nil?

        code = @user_code.s_value.gsub(/\$#{index + 1}/, inline_rhs.user_code.s_value)
        @user_code.references.each do |ref|
          next if ref.index.nil? || ref.index <= index # nil is a case for `$$`
          code = code.gsub(/\$#{ref.index}/, "$#{ref.index + (inline_rhs.symbols.count-1)}")
          code = code.gsub(/@#{ref.index}/, "@#{ref.index + (inline_rhs.symbols.count-1)}")
        end
        Lrama::Lexer::Token::UserCode.new(s_value: code, location: @user_code.location)
      end
    end
  end
end
