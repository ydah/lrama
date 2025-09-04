# rbs_inline: enabled
# frozen_string_literal: true

require "stringio"

module Lrama
  class Reporter
    class States
      # @rbs (?itemsets: bool, ?lookaheads: bool, ?solved: bool, ?counterexamples: bool, ?verbose: bool, ?mode: Symbol, **untyped _) -> void
      def initialize(itemsets: false, lookaheads: false, solved: false, counterexamples: false, verbose: false, mode: :text, **_)
        @itemsets = itemsets
        @lookaheads = lookaheads
        @solved = solved
        @counterexamples = counterexamples
        @verbose = verbose
        @mode = mode
      end

      # @rbs (IO io, Lrama::States states, ielr: bool) -> void
      def report(io, states, ielr: false)
        cex = Counterexamples.new(states) if @counterexamples
        states.compute_la_sources_for_conflicted_states

        case @mode
        when :text
          report_text(io, states, ielr: ielr, cex: cex)
        when :html
          report_html(io, states, ielr: ielr, cex: cex)
        else
          raise "Unknown mode: #{@mode.inspect}"
        end
      end

      private

      # @rbs (IO io, Lrama::States states, ielr: bool, cex: Lrama::Counterexamples?) -> void
      def report_html(io, states, ielr:, cex:)
        io << %Q(<div id="states">\n  <h2>State Machine</h2>\n\n)
        report_split_states_html(io, states.states) if ielr

        states.states.each do |state|
          io << %Q(  <div id="state-#{state.id}" class="state-block">\n)
          io << %Q(    <h3>State #{state.id}</h3>\n)
          io << %Q(    <pre>)

          report_items_html(io, state)
          report_conflicts_html(io, state)
          report_shifts_html(io, state)
          report_nonassoc_errors_html(io, state)
          report_reduces_html(io, state)
          report_nterm_transitions_html(io, state)
          report_conflict_resolutions_html(io, state) if @solved
          report_counterexamples_html(io, state, cex) if @counterexamples && state.has_conflicts?
          report_verbose_info_html(io, state, states) if @verbose

          io << %Q(</pre>\n)
          io << %Q(  </div>\n\n)
        end
        io << "</div>\n"
      end

      # @rbs (IO io, Array[Lrama::State] states) -> void
      def report_split_states_html(io, states)
        ss = states.select(&:split_state?)
        return if ss.empty?

        io << %Q(  <div id="split-states">\n)
        io << %Q(    <h3>Split States</h3>\n)
        io << %Q(    <pre>\n)
        ss.each { |state| io << sprintf("      State %d is split from state %d\n", state.id, state.lalr_isocore.id) }
        io << %Q(    </pre>\n)
        io << %Q(  </div>\n\n)
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_items_html(io, state)
        last_lhs = nil
        list = @itemsets ? state.items : state.kernels

        list.sort_by {|i| [i.rule_id, i.position] }.each do |item|
          r = if item.empty_rule?
            "&epsilon; &bull;" # ε •
          else
            item.rhs.map {|s| format_symbol_html(s) }.insert(item.position, "&bull;").join(" ")
          end

          l = if item.lhs == last_lhs
            " " * item.lhs.id.s_value.length + "|"
          else
            format_symbol_html(item.lhs) + ":"
          end

          la = ""
          if @lookaheads && item.end_of_rule?
            reduce = state.find_reduce_by_item!(item)
            look_ahead = reduce.selected_look_ahead
            unless look_ahead.empty?
              la = "  [#{look_ahead.compact.map {|s| format_symbol_html(s) }.join(", ")}]"
            end
          end

          last_lhs = item.lhs
          io << sprintf("%5d %s %s%s", item.rule_id, l, r, la) << "\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflicts_html(io, state)
        return if state.conflicts.empty?

        conflict_details = [] # @type var conflict_details: Array[String]
        state.conflicts.each do |conflict|
          syms_str = conflict.symbols.map { |s| format_symbol_html(s) }.join(", ")
          case conflict.type
          when :shift_reduce
            # @type var conflict: Lrama::State::ShiftReduceConflict
            io << "   <span class=\"conflict\">Conflict on #{syms_str}. shift/reduce(#{format_symbol_html(conflict.reduce.item.rule.lhs)})</span>\n"
            conflict_details << format_shift_reduce_conflict_detail(state, conflict)
          when :reduce_reduce
            # @type var conflict: Lrama::State::ReduceReduceConflict
            io << "   <span class=\"conflict\">Conflict on #{syms_str}. reduce/reduce(#{format_symbol_html(conflict.reduce1.item.rule.lhs)}/#{format_symbol_html(conflict.reduce2.item.rule.lhs)})</span>\n"
            conflict_details << format_reduce_reduce_conflict_detail(state, conflict)
          end
        end
        io << "\n"

        unless conflict_details.empty?
          io << %Q(<div class="conflict-detail">)
          io << conflict_details.join("\n")
          io << %Q(</div>)
        end
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_shifts_html(io, state)
        shifts = state.term_transitions.reject(&:not_selected)
        return if shifts.empty?

        max_len = shifts.map { |s| s.next_sym.display_name.length }.max || 0
        padding = 30 # spanタグの長さを考慮したおおよその値
        shifts.each do |shift|
          state_link = %Q(<a href="#state-#{shift.to_state.id}">go to state #{shift.to_state.id}</a>)
          io << "   #{format_symbol_html(shift.next_sym).ljust(max_len + padding)}  <span class=\"action\">shift</span>, and #{state_link}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nonassoc_errors_html(io, state)
        error_symbols = state.resolved_conflicts.select { |r| r.which == :error }.map(&:symbol)
        return if error_symbols.empty?

        max_len = error_symbols.map { |s| s.display_name.length }.max || 0
        padding = 30
        error_symbols.each do |sym|
          io << "   #{format_symbol_html(sym).ljust(max_len + padding)}  <span class=\"conflict\">error (nonassociative)</span>\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_reduces_html(io, state)
        reduce_pairs = [] # @type var reduce_pairs: Array[untyped]
        state.non_default_reduces.each { |r| r.look_ahead&.each { |t| reduce_pairs << [t, r] } }

        return if reduce_pairs.empty? && !state.default_reduction_rule

        all_symbols = reduce_pairs.map(&:first)
        all_symbols << Lrama::Lexer::Token::Ident.new(s_value: "$default") if state.default_reduction_rule
        max_len = [reduce_pairs.map(&:first).map(&:display_name).map(&:length).max || 0, state.default_reduction_rule ? "$default".length : 0].max
        padding = 30

        reduce_pairs.sort_by { |term, _| term.number }.each do |term, reduce|
          rule = reduce.item.rule
          rule_link = %Q(<a href="#rule-#{rule.id}">rule #{rule.id} (#{format_symbol_html(rule.lhs)})</a>)
          io << "   #{format_symbol_html(term).ljust(max_len + padding)}  <span class=\"action\">reduce</span> using #{rule_link}\n"
        end

        if (r = state.default_reduction_rule)
          s = "$default".ljust(max_len)
          if r.initial_rule?
            io << "   #{s}  <span class=\"action\">accept</span>\n"
          else
            rule_link = %Q(<a href="#rule-#{r.id}">rule #{r.id} (#{format_symbol_html(r.lhs)})</a>)
            io << "   #{s}  <span class=\"action\">reduce</span> using #{rule_link}\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nterm_transitions_html(io, state)
        return if state.nterm_transitions.empty?

        sorted = state.nterm_transitions.sort_by { |g| g.next_sym.number }
        max_len = sorted.map { |g| g.next_sym.id.s_value.length }.max || 0
        padding = 35

        sorted.each do |goto|
          state_link = %Q(<a href="#state-#{goto.to_state.id}">go to state #{goto.to_state.id}</a>)
          io << "   #{format_symbol_html(goto.next_sym).ljust(max_len + padding)}  #{state_link}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflict_resolutions_html(io, state)
        return if state.resolved_conflicts.empty?
        state.resolved_conflicts.each do |resolved|
          io << "    #{resolved.report_message}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::Counterexamples?) -> void
      def report_counterexamples_html(io, state, cex)
        return unless cex
        examples = cex.compute(state)
        return if examples.empty?
        io << "   <span class=\"debug-header\">[Counterexamples]</span>\n"
        examples.each do |ex|
          io << "    #{ex.map { |s| format_symbol_html(s) }.join(" ")}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_verbose_info_html(io, state, states)
        io << %Q(\n<span class="debug-info">)
        report_direct_read_sets_html(io, state, states)
        report_reads_relation_html(io, state, states)
        report_read_sets_html(io, state, states)
        report_includes_relation_html(io, state, states)
        report_lookback_relation_html(io, state, states)
        report_follow_sets_html(io, state, states)
        report_look_ahead_sets_html(io, state, states)
        io << %Q(</span>)
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_direct_read_sets_html(io, state, states)
        io << %Q( <span class="debug-header">[Direct Read sets]</span>\n)
        sets = states.direct_read_sets
        state.nterm_transitions.each do |goto|
          terms = sets[goto]
          next if !terms || terms.empty?
          terms_str = terms.map { |s| format_symbol_html(s) }.join(", ")
          io << "   read #{format_symbol_html(goto.next_sym)}  shift #{terms_str}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_reads_relation_html(io, state, states)
        io << %Q( <span class="debug-header">[Reads Relation]</span>\n)
        state.nterm_transitions.each do |goto|
          goto2_list = states.reads_relation[goto]
          next unless goto2_list
          goto2_list.each do |goto2|
            io << "   (#{link_to_state_html(goto2.from_state)}, #{format_symbol_html(goto2.next_sym)})\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_read_sets_html(io, state, states)
        io << %Q( <span class="debug-header">[Read sets]</span>\n)
        sets = states.read_sets
        state.nterm_transitions.each do |goto|
          terms = sets[goto]
          next if !terms || terms.empty?
          terms.each do |sym|
            io << "   #{format_symbol_html(sym)}\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_includes_relation_html(io, state, states)
        io << %Q( <span class="debug-header">[Includes Relation]</span>\n)
        state.nterm_transitions.each do |goto|
          gotos = states.includes_relation[goto]
          next unless gotos
          gotos.each do |goto2|
            io << "   (#{link_to_state_html(state)}, #{format_symbol_html(goto.next_sym)}) -&gt; (#{link_to_state_html(goto2.from_state)}, #{format_symbol_html(goto2.next_sym)})\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_lookback_relation_html(io, state, states)
        io << %Q( <span class="debug-header">[Lookback Relation]</span>\n)
        states.rules.each do |rule|
          gotos = states.lookback_relation[[state.id, rule.id]]
          next unless gotos

          lhs_html = format_symbol_html(rule.lhs)
          rhs_html = if rule.empty_rule?
                      "&epsilon;"
                    else
                      rule.rhs.map { |sym| format_symbol_html(sym) }.join(" ")
                    end
          rule_text = "#{lhs_html} -&gt; #{rhs_html}"

          gotos.each do |goto2|
            io << "   (Rule: #{link_to_rule_html(rule, rule_text)}) -&gt; (#{link_to_state_html(goto2.from_state)}, #{format_symbol_html(goto2.next_sym)})\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_follow_sets_html(io, state, states)
        io << %Q( <span class="debug-header">[Follow sets]</span>\n)
        sets = states.follow_sets
        state.nterm_transitions.each do |goto|
          terms = sets[goto]
          next unless terms
          terms.each do |sym|
            io << "   #{format_symbol_html(goto.next_sym)} -&gt; #{format_symbol_html(sym)}\n"
          end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_look_ahead_sets_html(io, state, states)
        io << %Q( <span class="debug-header">[Look-Ahead Sets]</span>\n)
        look_ahead_rules = [] # @type var look_ahead_rules: Array[untyped]
        states.rules.each do |rule|
          syms = states.la[[state.id, rule.id]]
          look_ahead_rules << [rule, syms] if syms
        end
        return if look_ahead_rules.empty?

        max_len = look_ahead_rules.flat_map { |_, syms| syms.map { |s| s.id.s_value.length } }.max || 0
        padding = 30
        look_ahead_rules.each do |rule, syms|
          syms.each do |sym|
            rule_link = %Q(<a href="#rule-#{rule.id}">rule #{rule.id} (#{format_symbol_html(rule.lhs)})</a>)
            io << "   #{format_symbol_html(sym).ljust(max_len + padding)}  <span class=\"action\">reduce</span> using #{rule_link}\n"
          end
        end
        io << "\n"
      end

      # @rbs (Lrama::State state, Lrama::State::ShiftReduceConflict conflict) -> String
      def format_shift_reduce_conflict_detail(state, conflict)
        conflict_symbol = conflict.symbols.first
        shift_item = state.items.find { |i| i.next_sym == conflict_symbol }

        shift_item_html = if shift_item
          format_item_html(shift_item, with_rule_id: false)
        else
          "Shift rule not found"
        end

        reduce_item_html = format_item_html(conflict.reduce.item, with_rule_id: false)
        sym_html = format_symbol_html(conflict_symbol)
        shift_rule = shift_item&.rule

        details = [
          "   shift/reduce conflict on token #{sym_html}:",
        ]
        details << "     " + (shift_rule ? link_to_rule_html(shift_rule, shift_item_html) : shift_item_html)
        details << "     " + link_to_rule_html(conflict.reduce.item.rule, reduce_item_html)

        details.join("\n")
      end

      # @rbs (Lrama::State state, Lrama::State::ReduceReduceConflict conflict) -> String
      def format_reduce_reduce_conflict_detail(state, conflict)
        reduce1_html = format_item_html(conflict.reduce1.item, with_rule_id: false)
        reduce2_html = format_item_html(conflict.reduce2.item, with_rule_id: false)

        details = [
          "   reduce/reduce conflict:",
          "     " + link_to_rule_html(conflict.reduce1.item.rule, reduce1_html),
          "     " + link_to_rule_html(conflict.reduce2.item.rule, reduce2_html),
        ]
        details.join("\n")
      end

      # @rbs (Lrama::Grammar::Symbol symbol) -> String
      def format_symbol_html(symbol)
        display_name = symbol.display_name
        case
        when symbol.term?
          %Q(<span class="token">#{display_name}</span>)
        when symbol.nterm?
          %Q(<span class="non-terminal">#{display_name}</span>)
        else
          display_name
        end
      end

      # @rbs (Lrama::State state) -> String
      def link_to_state_html(state)
        %Q(<a href="#state-#{state.id}">State #{state.id}</a>)
      end

      # @rbs (Lrama::Grammar::Rule rule, String text) -> String
      def link_to_rule_html(rule, text)
        %Q(<a href="#rule-#{rule.id}">#{text}</a>)
      end

      # @rbs (Lrama::State::Item item, ?with_rule_id: bool, ?with_position: bool) -> String
      def format_item_html(item, with_rule_id: true, with_position: true)
        rule = item.rule
        parts = [] # @type var parts: Array[String]
        parts << rule.id.to_s if with_rule_id
        parts << "#{format_symbol_html(rule.lhs)}:"

        rhs = if rule.empty_rule?
          ["&epsilon;"]
        else
          rule.rhs.map { |s| format_symbol_html(s) }
        end

        rhs.insert(item.position, "&bull;") if with_position
        parts << rhs.join(" ")
        parts.join(" ")
      end

      # @rbs (IO io, Lrama::States states, ielr: bool, cex: Lrama::Counterexamples?) -> void
      def report_text(io, states, ielr:, cex:)
        report_split_states(io, states.states) if ielr
        states.states.each do |state|
          report_state_header(io, state)
          report_items(io, state)
          report_conflicts(io, state)
          report_shifts(io, state)
          report_nonassoc_errors(io, state)
          report_reduces(io, state)
          report_nterm_transitions(io, state)
          report_conflict_resolutions(io, state) if @solved
          report_counterexamples(io, state, cex) if @counterexamples && state.has_conflicts?
          report_verbose_info(io, state, states) if @verbose
          io << "\n"
        end
      end

      # @rbs (IO io, Array[Lrama::State] states) -> void
      def report_split_states(io, states)
        ss = states.select(&:split_state?)
        return if ss.empty?
        io << "Split States\n\n"
        ss.each { |state| io << "    State #{state.id} is split from state #{state.lalr_isocore.id}\n" }
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_state_header(io, state)
        io << "State #{state.id}\n\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_items(io, state)
        last_lhs = nil
        list = @itemsets ? state.items : state.kernels
        list.sort_by {|i| [i.rule_id, i.position] }.each do |item|
          r = item.empty_rule? ? "ε •" : item.rhs.map(&:display_name).insert(item.position, "•").join(" ")
          l = if item.lhs == last_lhs then " " * item.lhs.id.s_value.length + "|" else item.lhs.id.s_value + ":" end
          la = ""
          if @lookaheads && item.end_of_rule?
            reduce = state.find_reduce_by_item!(item)
            look_ahead = reduce.selected_look_ahead
            unless look_ahead.empty? then la = "  [#{look_ahead.compact.map(&:display_name).join(", ")}]" end
          end
          last_lhs = item.lhs
          io << sprintf("%5i %s %s%s", item.rule_id, l, r, la) << "\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflicts(io, state)
        return if state.conflicts.empty?
        state.conflicts.each do |conflict|
          syms = conflict.symbols.map { |sym| sym.display_name }
          io << "    Conflict on #{syms.join(", ")}. "
          case conflict.type
          when :shift_reduce
            io << "shift/reduce(#{conflict.reduce.item.rule.lhs.display_name})\n" # @type var conflict: Lrama::State::ShiftReduceConflict
            conflict.symbols.each do |token|
              conflict.reduce.look_ahead_sources[token].each { |goto| io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n" } # steep:ignore NoMethod
            end
          when :reduce_reduce
            io << "reduce(#{conflict.reduce1.item.rule.lhs.display_name})/reduce(#{conflict.reduce2.item.rule.lhs.display_name})\n" # @type var conflict: Lrama::State::ReduceReduceConflict
            conflict.symbols.each do |token|
              conflict.reduce1.look_ahead_sources[token].each { |goto| io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n" } # steep:ignore NoMethod
              conflict.reduce2.look_ahead_sources[token].each { |goto| io << "      #{token.display_name} comes from state #{goto.from_state.id} goto by #{goto.next_sym.display_name}\n" } # steep:ignore NoMethod
            end
          else
            raise "Unknown conflict type #{conflict.type}"
          end
          io << "\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_shifts(io, state)
        shifts = state.term_transitions.reject(&:not_selected)
        return if shifts.empty?
        max_len = shifts.map(&:next_sym).map(&:display_name).map(&:length).max
        shifts.each { |shift| io << "    #{shift.next_sym.display_name.ljust(max_len)}  shift, and go to state #{shift.to_state.id}\n" }
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nonassoc_errors(io, state)
        error_symbols = state.resolved_conflicts.select { |resolved| resolved.which == :error }.map { |error| error.symbol.display_name }
        return if error_symbols.empty?
        max_len = error_symbols.map(&:length).max
        error_symbols.each { |name| io << "    #{name.ljust(max_len)}  error (nonassociative)\n" }
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_reduces(io, state)
        reduce_pairs = [] #: Array[[Lrama::Grammar::Symbol, Lrama::State::Action::Reduce]]
        state.non_default_reduces.each { |reduce| reduce.look_ahead&.each { |term| reduce_pairs << [term, reduce] } }
        return if reduce_pairs.empty? && !state.default_reduction_rule
        max_len = [reduce_pairs.map(&:first).map(&:display_name).map(&:length).max || 0, state.default_reduction_rule ? "$default".length : 0].max
        reduce_pairs.sort_by { |term, _| term.number }.each do |term, reduce|
          rule = reduce.item.rule
          io << "    #{term.display_name.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.display_name})\n"
        end
        if (r = state.default_reduction_rule)
          s = "$default".ljust(max_len)
          if r.initial_rule? then io << "    #{s}  accept\n" else io << "    #{s}  reduce using rule #{r.id} (#{r.lhs.display_name})\n" end
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_nterm_transitions(io, state)
        return if state.nterm_transitions.empty?
        goto_transitions = state.nterm_transitions.sort_by { |goto| goto.next_sym.number }
        max_len = goto_transitions.map(&:next_sym).map { |nterm| nterm.id.s_value.length }.max
        goto_transitions.each { |goto| io << "    #{goto.next_sym.id.s_value.ljust(max_len)}  go to state #{goto.to_state.id}\n" }
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state) -> void
      def report_conflict_resolutions(io, state)
        return if state.resolved_conflicts.empty?
        state.resolved_conflicts.each { |resolved| io << "    #{resolved.report_message}\n" }
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::Counterexamples? cex) -> void
      def report_counterexamples(io, state, cex)
        return unless cex
        examples = cex.compute(state)
        examples.each do |example|
          is_shift_reduce = example.type == :shift_reduce
          label0 = is_shift_reduce ? "shift/reduce" : "reduce/reduce"
          label1 = is_shift_reduce ? "Shift derivation" : "First Reduce derivation"
          label2 = is_shift_reduce ? "Reduce derivation" : "Second Reduce derivation"
          io << "    #{label0} conflict on token #{example.conflict_symbol.id.s_value}:\n"
          io << "        #{example.path1_item}\n"
          io << "        #{example.path2_item}\n"
          io << "      #{label1}\n"
          example.derivations1.render_strings_for_report.each { |str| io << "        #{str}\n" }
          io << "      #{label2}\n"
          example.derivations2.render_strings_for_report.each { |str| io << "        #{str}\n" }
        end
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_verbose_info(io, state, states)
        report_direct_read_sets(io, state, states)
        report_reads_relation(io, state, states)
        report_read_sets(io, state, states)
        report_includes_relation(io, state, states)
        report_lookback_relation(io, state, states)
        report_follow_sets(io, state, states)
        report_look_ahead_sets(io, state, states)
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_direct_read_sets(io, state, states)
        io << "  [Direct Read sets]\n"
        direct_read_sets = states.direct_read_sets
        state.nterm_transitions.each do |goto|
          terms = direct_read_sets[goto]
          next unless terms && !terms.empty?
          str = terms.map { |sym| sym.id.s_value }.join(", ")
          io << "    read #{goto.next_sym.id.s_value}  shift #{str}\n"
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_reads_relation(io, state, states)
        io << "  [Reads Relation]\n"
        state.nterm_transitions.each do |goto|
          goto2 = states.reads_relation[goto]
          next unless goto2
          goto2.each { |goto2| io << "    (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n" }
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_read_sets(io, state, states)
        io << "  [Read sets]\n"
        read_sets = states.read_sets
        state.nterm_transitions.each do |goto|
          terms = read_sets[goto]
          next unless terms && !terms.empty?
          terms.each { |sym| io << "    #{sym.id.s_value}\n" }
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_includes_relation(io, state, states)
        io << "  [Includes Relation]\n"
        state.nterm_transitions.each do |goto|
          gotos = states.includes_relation[goto]
          next unless gotos
          gotos.each { |goto2| io << "    (State #{state.id}, #{goto.next_sym.id.s_value}) -> (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n" }
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_lookback_relation(io, state, states)
        io << "  [Lookback Relation]\n"
        states.rules.each do |rule|
          gotos = states.lookback_relation[[state.id, rule.id]]
          next unless gotos
          gotos.each { |goto2| io << "    (Rule: #{rule.display_name}) -> (State #{goto2.from_state.id}, #{goto2.next_sym.id.s_value})\n" }
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_follow_sets(io, state, states)
        io << "  [Follow sets]\n"
        follow_sets = states.follow_sets
        state.nterm_transitions.each do |goto|
          terms = follow_sets[goto]
          next unless terms
          terms.each { |sym| io << "    #{goto.next_sym.id.s_value} -> #{sym.id.s_value}\n" }
        end
        io << "\n"
      end

      # @rbs (IO io, Lrama::State state, Lrama::States states) -> void
      def report_look_ahead_sets(io, state, states)
        io << "  [Look-Ahead Sets]\n"
        look_ahead_rules = [] #: Array[[Lrama::Grammar::Rule, Array[Lrama::Grammar::Symbol]]]
        states.rules.each do |rule|
          syms = states.la[[state.id, rule.id]]
          next unless syms
          look_ahead_rules << [rule, syms]
        end
        return if look_ahead_rules.empty?
        max_len = look_ahead_rules.flat_map { |_, syms| syms.map { |s| s.id.s_value.length } }.max
        look_ahead_rules.each do |rule, syms|
          syms.each { |sym| io << "    #{sym.id.s_value.ljust(max_len)}  reduce using rule #{rule.id} (#{rule.lhs.id.s_value})\n" }
        end
        io << "\n"
      end
    end
  end
end
