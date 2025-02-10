# frozen_string_literal: true

module Lrama
  class Grammar
    class RuleBuilder
      attr_accessor :lhs, :line
      attr_reader :rule_counter, :midrule_action_counter, :parameterized_resolver,
                  :lhs_tag, :rhs, :user_code, :precedence_sym

      def initialize(rule_counter, midrule_action_counter, parameterized_resolver, position_in_original_rule_rhs = nil, lhs_tag: nil, skip_preprocess_references: false)
        @rule_counter = rule_counter
        @midrule_action_counter = midrule_action_counter
        @parameterized_resolver = parameterized_resolver
        @position_in_original_rule_rhs = position_in_original_rule_rhs
        @skip_preprocess_references = skip_preprocess_references

        @lhs = nil
        @lhs_tag = lhs_tag
        @rhs = []
        @user_code = nil
        @precedence_sym = nil
        @line = nil
        @rules = []
        @rule_builders_for_parameterized = []
        @rule_builders_for_derived_rules = []
        @parameterized_rules = []
        @midrule_action_rules = []
      end

      def add_rhs(rhs)
        @line ||= rhs.line

        flush_user_code

        @rhs << rhs
      end

      def user_code=(user_code)
        @line ||= user_code&.line

        flush_user_code

        @user_code = user_code
      end

      def precedence_sym=(precedence_sym)
        flush_user_code

        @precedence_sym = precedence_sym
      end

      def complete_input
        freeze_rhs
      end

      def setup_rules
        preprocess_references unless @skip_preprocess_references
        process_rhs
        build_rules
      end

      def rules
        @parameterized_rules + @midrule_action_rules + @rules
      end

      def has_inline_rules?
        rhs.any? { |token| @parameterized_resolver.find_inline(token) }
      end

      private

      def freeze_rhs
        @rhs.freeze
      end

      def preprocess_references
        numberize_references
      end

      def build_rules
        tokens = @replaced_rhs

        rule = Rule.new(
          id: @rule_counter.increment, _lhs: lhs, _rhs: tokens, lhs_tag: lhs_tag, token_code: user_code,
          position_in_original_rule_rhs: @position_in_original_rule_rhs, precedence_sym: precedence_sym, lineno: line
        )
        @rules = [rule]
        @parameterized_rules = @rule_builders_for_parameterized.map do |rule_builder|
          rule_builder.rules
        end.flatten
        @midrule_action_rules = @rule_builders_for_derived_rules.map do |rule_builder|
          rule_builder.rules
        end.flatten
        @midrule_action_rules.each do |r|
          r.original_rule = rule
        end
      end

      # rhs is a mixture of variety type of tokens like `Ident`, `InstantiateRule`, `UserCode` and so on.
      # `#process_rhs` replaces some kind of tokens to `Ident` so that all `@replaced_rhs` are `Ident` or `Char`.
      def process_rhs
        return if @replaced_rhs

        @replaced_rhs = []

        rhs.each_with_index do |token, i|
          case token
          when Lrama::Lexer::Token::Char
            @replaced_rhs << token
          when Lrama::Lexer::Token::Ident
            @replaced_rhs << token
          when Lrama::Lexer::Token::InstantiateRule
            parameterized_rule = @parameterized_resolver.find_rule(token)
            raise "Unexpected token. #{token}" unless parameterized_rule

            bindings = Binding.new(parameterized_rule.parameters, token.args)
            lhs_s_value = bindings.concatenated_args_str(token)
            if (created_lhs = @parameterized_resolver.created_lhs(lhs_s_value))
              @replaced_rhs << created_lhs
            else
              lhs_token = Lrama::Lexer::Token::Ident.new(s_value: lhs_s_value, location: token.location)
              @replaced_rhs << lhs_token
              @parameterized_resolver.created_lhs_list << lhs_token
              parameterized_rule.rhs.each do |r|
                rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, @parameterized_resolver, lhs_tag: token.lhs_tag || parameterized_rule.tag)
                rule_builder.lhs = lhs_token
                r.symbols.each { |sym| rule_builder.add_rhs(bindings.resolve_symbol(sym)) }
                rule_builder.line = line
                rule_builder.precedence_sym = r.precedence_sym
                rule_builder.user_code = r.resolve_user_code(bindings)
                rule_builder.complete_input
                rule_builder.setup_rules
                @rule_builders_for_parameterized << rule_builder
              end
            end
          when Lrama::Lexer::Token::UserCode
            prefix = token.referred ? "@" : "$@"
            tag = token.tag || lhs_tag
            new_token = Lrama::Lexer::Token::Ident.new(s_value: prefix + @midrule_action_counter.increment.to_s)
            @replaced_rhs << new_token

            rule_builder = RuleBuilder.new(@rule_counter, @midrule_action_counter, @parameterized_resolver, i, lhs_tag: tag, skip_preprocess_references: true)
            rule_builder.lhs = new_token
            rule_builder.user_code = token
            rule_builder.complete_input
            rule_builder.setup_rules

            @rule_builders_for_derived_rules << rule_builder
          else
            raise "Unexpected token. #{token}"
          end
        end
      end

      def numberize_references
        # Bison n'th component is 1-origin
        (rhs + [user_code]).compact.each.with_index(1) do |token, i|
          next unless token.is_a?(Lrama::Lexer::Token::UserCode)

          token.references.each do |ref|
            ref_name = ref.name

            if ref_name
              if ref_name == '$'
                ref.name = '$'
              else
                candidates = ([lhs] + rhs).each_with_index.select {|token, _i| token.referred_by?(ref_name) }

                if candidates.size >= 2
                  token.invalid_ref(ref, "Referring symbol `#{ref_name}` is duplicated.")
                end

                unless (referring_symbol = candidates.first)
                  token.invalid_ref(ref, "Referring symbol `#{ref_name}` is not found.")
                end

                if referring_symbol[1] == 0 # Refers to LHS
                  ref.name = '$'
                else
                  ref.number = referring_symbol[1]
                end
              end
            end

            if ref.number
              ref.index = ref.number
            end

            # TODO: Need to check index of @ too?
            next if ref.type == :at

            if ref.index
              # TODO: Prohibit $0 even so Bison allows it?
              # See: https://www.gnu.org/software/bison/manual/html_node/Actions.html
              token.invalid_ref(ref, "Can not refer following component. #{ref.index} >= #{i}.") if ref.index >= i
              rhs[ref.index - 1].referred = true
            end
          end
        end
      end

      def flush_user_code
        if (c = @user_code)
          @rhs << c
          @user_code = nil
        end
      end
    end
  end
end
