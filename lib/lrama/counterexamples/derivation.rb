# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    class Derivation
      # @rbs!
      #   @item: States::Item
      #   @left: Derivation?

      attr_reader :item  #: States::Item
      attr_reader :left  #: Derivation?
      attr_accessor :right #: Derivation?

      # @rbs (States::Item item, Derivation? left) -> void
      def initialize(item, left)
        @item = item
        @left = left
      end

      # @rbs () -> ::String
      def to_s
        "#<Derivation(#{item.display_name})>"
      end
      alias :inspect :to_s

      # @rbs () -> Array[String]
      def render_strings_for_report
        result = [] #: Array[String]
        _render_for_report(self, 0, result, 0)
        result.map(&:rstrip)
      end

      # @rbs () -> String
      def render_for_report
        render_strings_for_report.join("\n")
      end

      private

      # @rbs (Derivation derivation, Integer offset, Array[String] strings, Integer index) -> Integer
      def _render_for_report(derivation, offset, strings, index)
        item = derivation.item
        if strings[index]
          strings[index] << " " * (offset - strings[index].length)
        else
          strings[index] = " " * offset
        end
        str = strings[index]
        str << "#{item.rule_id}: #{item.symbols_before_dot.map(&:display_name).join(" ")} "

        if derivation.left
          len = str.length
          str << "#{item.next_sym.display_name}"
          length = _render_for_report(derivation.left, len, strings, index + 1)
          # I want String#ljust!
          str << " " * (length - str.length) if length > str.length
        else
          str << " • #{item.symbols_after_dot.map(&:display_name).join(" ")} "
          return str.length
        end

        if derivation.right&.left
          left = derivation.right&.left #: Derivation
          length = _render_for_report(left, str.length, strings, index + 1)
          str << "#{item.symbols_after_dot[1..-1].map(&:display_name).join(" ")} " # steep:ignore
          str << " " * (length - str.length) if length > str.length
        elsif item.next_next_sym
          str << "#{item.symbols_after_dot[1..-1].map(&:display_name).join(" ")} " # steep:ignore
        end

        return str.length
      end
    end
  end
end
