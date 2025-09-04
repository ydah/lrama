# rbs_inline: enabled
# frozen_string_literal: true

require "cgi"

module Lrama
  class Reporter
    class Grammar
      # @rbs (?grammar: bool, ?mode: Symbol, **untyped _) -> void
      def initialize(grammar: false, mode: :text, **_)
        @grammar = grammar
        @mode = mode
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @grammar

        case @mode
        when :text
          report_text(io, states)
        when :html
          report_html(io, states)
        else
          raise "Unknown mode: #{@mode.inspect}"
        end
      end

      private

      # @rbs (IO io, Lrama::States states) -> void
      def report_html(io, states)
        io << %Q(<div id="grammar">\n)
        io << %Q(  <h2>Grammar</h2>\n)
        io << %Q(  <ol start="0" class="grammar-list">\n)

        states.rules.each do |rule|
          lhs_html = format_symbol_html(rule.lhs)

          rhs_html = if rule.empty_rule?
                       "&epsilon;"
                     else
                       rule.rhs.map { |sym| format_symbol_html(sym) }.join(" ")
                     end

          io << %Q(    <li id="rule-#{rule.id}">#{lhs_html}: #{rhs_html}</li>\n)
        end

        io << %Q(  </ol>\n)
        io << %Q(</div>\n)
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report_text(io, states)
        io << "Grammar\n"
        last_lhs = nil

        states.rules.each do |rule|
          if rule.empty_rule?
            r = "ε"
          else
            r = rule.rhs.map(&:display_name).join(" ")
          end

          if rule.lhs == last_lhs
            io << sprintf("%5d %s| %s", rule.id, " " * rule.lhs.display_name.length, r) << "\n"
          else
            io << "\n"
            io << sprintf("%5d %s: %s", rule.id, rule.lhs.display_name, r) << "\n"
          end

          last_lhs = rule.lhs
        end
        io << "\n\n"
      end

      # @rbs (Lrama::Grammar::Symbol symbol) -> String
      def format_symbol_html(symbol)
        case
        when symbol.term?
          %Q(<span class="token">#{symbol.display_name}</span>)
        when symbol.nterm?
          %Q(<span class="non-terminal">#{symbol.display_name}</span>)
        else
          symbol.display_name
        end
      end
    end
  end
end
