# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Parameterized
      class Resolver
        attr_accessor :rules #: Array[Rule]
        attr_accessor :created_lhs_list #: Array[Lexer::Token]

        # @rbs () -> void
        def initialize
          @rules = []
          @created_lhs_list = []
        end

        # @rbs (Rule rule) -> Array[Rule]
        def add_parameterizing_rule(rule)
          @rules << rule
        end

        # @rbs (Lexer::Token::InstantiateRule token) -> Rule?
        def find_rule(token)
          select_rules(@rules, token).last
        end

        # @rbs (Lexer::Token token) -> Rule?
        def find_inline(token)
          @rules.reverse.find { |rule| rule.name == token.s_value && rule.is_inline }
        end

        # @rbs (String lhs_s_value) -> Lexer::Token?
        def created_lhs(lhs_s_value)
          @created_lhs_list.reverse.find { |created_lhs| created_lhs.s_value == lhs_s_value }
        end

        # @rbs () -> Array[Rule]
        def redefined_rules
          @rules.select { |rule| @rules.count { |r| r.name == rule.name && r.required_parameters_count == rule.required_parameters_count } > 1 }
        end

        private

        # @rbs (Array[Rule] rules, Lexer::Token::InstantiateRule token) -> Array[Rule]
        def select_rules(rules, token)
          rules = select_not_inline_rules(rules)
          rules = select_rules_by_name(rules, token.rule_name)
          rules = rules.select { |rule| rule.required_parameters_count == token.args_count }
          if rules.empty?
            raise "Invalid number of arguments. `#{token.rule_name}`"
          else
            rules
          end
        end

        # @rbs (Array[Rule] rules) -> Array[Rule]
        def select_not_inline_rules(rules)
          rules.select { |rule| !rule.is_inline }
        end

        # @rbs (Array[Rule] rules, String rule_name) -> Array[Rule]
        def select_rules_by_name(rules, rule_name)
          rules = rules.select { |rule| rule.name == rule_name }
          if rules.empty?
            raise "Parameterizing rule does not exist. `#{rule_name}`"
          else
            rules
          end
        end
      end
    end
  end
end
