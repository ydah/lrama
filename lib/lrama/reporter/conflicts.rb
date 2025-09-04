# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Conflicts
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
        conflicted_states = states.states.select { |s| s.conflicts.any? }
        return if conflicted_states.empty?

        io.puts "        <h3>Conflicts</h3>"
        io.puts "        <ul>"
        conflicted_states.each do |state|
          messages = format_conflict_messages(state.conflicts).join(', ')
          io.puts %Q(          <li><span class="conflict"><a href="#state-#{state.id}">State #{state.id}</a> conflicts: #{messages}</span></li>)
        end
        io.puts "        </ul>"
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report_text(io, states)
        has_conflict = false
        states.states.each do |state|
          messages = format_conflict_messages(state.conflicts)
          unless messages.empty?
            has_conflict = true
            io << "State #{state.id} conflicts: #{messages.join(', ')}\n"
          end
        end
        io << "\n\n" if has_conflict
      end

      # @rbs (Array[(Lrama::State::ShiftReduceConflict | Lrama::State::ReduceReduceConflict)] conflicts) -> Array[String]
      def format_conflict_messages(conflicts)
        conflict_types = {
          shift_reduce: "shift/reduce",
          reduce_reduce: "reduce/reduce"
        }
        conflict_types.keys.map do |type|
          type_conflicts = conflicts.select { |c| c.type == type }
          "#{type_conflicts.count} #{conflict_types[type]}" unless type_conflicts.empty?
        end.compact
      end
    end
  end
end
