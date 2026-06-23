require 'sparql/client'

module Goo
  module SPARQL
    # Goo-owned extensions that used to live in the forked sparql-client gem.
    # See docs/sparql-client-defork-proposal.md.
    module Ext
      # Builds the `OPTIONAL { { ..pattern.. BIND/FILTER } UNION { .. } }` group that goo
      # uses to pull included attributes (and their inverses) in a single query.
      #
      # This replaces the forked DSL (`SPARQL::Client::Query#optional_union_with_bind_as`
      # + `#add_union_with_bind`, and the `to_s` buffer surgery that injected them). It is a
      # plain `QueryElement` whose `to_s` is the rendered block, so the gem needs no patch:
      # goo pushes it onto the query's filter list, which renders each element verbatim
      # (no `FILTER(...)` wrapper, no trailing ` .`).
      #
      # `binding_as` is the structure built by Goo::SPARQL::QueryBuilder#union_bind_in_where:
      # an Array of `[triples, opts]`, where `triples` is an Array of `[s, p, o]` (symbols
      # for variables, RDF terms otherwise) and `opts` carries `:binds` and/or `:filters`.
      #
      # Output is byte-identical to the old fork DSL; locked by
      # test/test_sparql_query_characterization.rb.
      class UnionWithBind < ::SPARQL::Client::QueryElement
        def initialize(binding_as)
          super()
          @binding_as = binding_as
        end

        def empty?
          @binding_as.nil? || @binding_as.empty?
        end

        def to_s
          groups = @binding_as.map do |triples, opts|
            buffer = serialize_triples(triples)
            buffer += serialize_filters(opts[:filters]) if opts[:filters]
            buffer += serialize_binds(opts[:binds]) if opts[:binds]
            (['{'] + buffer + ['}']).join(' ')
          end
          'OPTIONAL { ' + groups.join(' UNION  ') + ' }'
        end

        private

        # Mirrors the fork's instance `serialize_patterns`: every position goes through
        # serialize_value (so symbols render as `?var`), with `a` for rdf:type.
        def serialize_triples(triples)
          triples.map do |triple|
            triple.map do |value|
              term = value.is_a?(Symbol) ? RDF::Query::Variable.new(value) : value
              term.equal?(RDF.type) ? 'a' : ::SPARQL::Client.serialize_value(term)
            end.join(' ') + ' .'
          end
        end

        def serialize_filters(filters)
          filters.map do |filter|
            clauses = filter[:values].map { |v| "?#{filter[:predicate]} = <#{v}>" }
            "FILTER(#{clauses.join(' || ')}) "
          end
        end

        def serialize_binds(binds)
          binds.map { |bind| "BIND( \"#{bind[:value]}\" as ?#{bind[:as]})" }
        end
      end
    end
  end
end
