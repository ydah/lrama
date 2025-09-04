# rbs_inline: enabled
# frozen_string_literal: true

require 'set'

module Lrama
  class Reporter
    class Terms
      # @rbs (?terms: bool, ?mode: Symbol, **untyped _) -> void
      def initialize(terms: false, mode: :text, **_)
        @terms = terms
        @mode = mode
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @terms

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
        unused_symbols = calculate_unused_symbols(states)

        io.puts "        <h3>Statistics</h3>"
        io.puts "        <ul>"
        io.puts "          <li>#{states.terms.count} Terms</li>"
        io.puts "          <li>#{states.nterms.count} Non-Terminals</li>"
        io.puts "          <li>#{unused_symbols.count} Unused Terms</li>" if unused_symbols.any?
        io.puts "        </ul>"
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report_text(io, states)
        unused_symbols = calculate_unused_symbols(states)

        io << "#{states.terms.count} Terms\n\n"
        io << "#{states.nterms.count} Non-Terminals\n\n"

        unless unused_symbols.empty?
          io << "#{unused_symbols.count} Unused Terms\n\n"
          unused_symbols.each_with_index do |term, index|
            # @type var term: Lrama::Grammar::Symbol
            io << sprintf("%5d %s", index, term.id.s_value) << "\n"
          end
          io << "\n\n"
        end
      end

      # @rbs (Lrama::States states) -> Array[untyped]
      def calculate_unused_symbols(states)
        look_aheads = states.states.flat_map do |state|
          state.reduces.flat_map { |r| r.look_ahead || [] }
        end
        next_terms = states.states.flat_map do |state|
          state.term_transitions.map(&:next_sym)
        end
        used_symbols = Set.new(look_aheads + next_terms)
        states.terms.reject { |term| used_symbols.include?(term) }
      end
    end
  end
end
