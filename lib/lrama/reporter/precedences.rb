# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Precedences
      # @rbs (?mode: Symbol, **untyped _) -> void
      def initialize(mode: :text, **_)
        @mode = mode
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
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
        used_precedences = states.precedences.select(&:used_by?)

        return if used_precedences.empty?

        io << %Q(<div id="precedences">\n)
        io << %Q(  <h2>Precedence Resolution</h2>\n)
        io << %Q(  <pre class="code-block">\n)

        used_precedences.each do |precedence|
          io << "  precedence on #{format_symbol_html(precedence.symbol)} is used to resolve conflict on\n"

          if precedence.used_by_lalr?
            io << "    LALR\n"
            precedence.used_by_lalr.uniq.sort_by { |rc| rc.state.id }.each do |resolved_conflict|
              state_link = %Q(<a href="#state-#{resolved_conflict.state.id}">state #{resolved_conflict.state.id}</a>)
              # report_precedences_message may contain symbols, so we escape it for safety
              message = resolved_conflict.report_precedences_message
              io << "      #{state_link}. #{message}\n"
            end
            io << "\n"
          end

          if precedence.used_by_ielr?
            io << "    IELR\n"
            precedence.used_by_ielr.uniq.sort_by { |rc| rc.state.id }.each do |resolved_conflict|
              state_link = %Q(<a href="#state-#{resolved_conflict.state.id}">state #{resolved_conflict.state.id}</a>)
              message = resolved_conflict.report_precedences_message
              io << "      #{state_link}. #{message}\n"
            end
            io << "\n"
          end
        end

        io << %Q(  </pre>\n)
        io << %Q(</div>\n)
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report_text(io, states)
        used_precedences = states.precedences.select(&:used_by?)

        return if used_precedences.empty?

        io << "Precedences\n\n"

        used_precedences.each do |precedence|
          io << "  precedence on #{precedence.symbol.display_name} is used to resolve conflict on\n"

          if precedence.used_by_lalr?
            io << "    LALR\n"

            precedence.used_by_lalr.uniq.sort_by do |resolved_conflict|
              resolved_conflict.state.id
            end.each do |resolved_conflict|
              io << "      state #{resolved_conflict.state.id}. #{resolved_conflict.report_precedences_message}\n"
            end

            io << "\n"
          end

          if precedence.used_by_ielr?
            io << "    IELR\n"

            precedence.used_by_ielr.uniq.sort_by do |resolved_conflict|
              resolved_conflict.state.id
            end.each do |resolved_conflict|
              io << "      state #{resolved_conflict.state.id}. #{resolved_conflict.report_precedences_message}\n"
            end

            io << "\n"
          end
        end

        io << "\n"
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
