#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Domgen
  class Sync
    VALID_MASTER_FACETS = [:sql, :mssql, :pgsql, :ee, :ejb, :java, :jpa, :sync, :syncrecord, :appconfig]
    VALID_SYNC_TEMP_FACETS = [:sql, :mssql, :pgsql, :sync, :syncrecord, :appconfig]
  end

  FacetManager.facet(:sync => [:syncrecord, :sql]) do |facet|
    facet.enhance(Repository) do

      def transaction_time=(transaction_time)
        @transaction_time = transaction_time
      end

      def transaction_time?
        @transaction_time.nil? ? false : !!@transaction_time
      end

      attr_writer :mapping_source_attribute

      def mapping_source_attribute
        @mapping_source_attribute || 'MappingSource'
      end

      attr_writer :master_data_module

      def master_data_module
        @master_data_module || 'Master'
      end

      attr_writer :sync_temp_data_module

      def sync_temp_data_module
        @sync_temp_data_module || 'SyncTemp'
      end

      def sync_out_of_master?
        @sync_out_of_master.nil? ? true : !!@sync_out_of_master
      end

      attr_writer :sync_out_of_master

      def pre_complete
        unless repository.data_module_by_name?(self.master_data_module)
          repository.data_module(self.master_data_module)
        end
        master_data_module = repository.data_module_by_name(self.master_data_module)

        unless repository.data_module_by_name?(self.sync_temp_data_module)
          repository.data_module(self.sync_temp_data_module)
        end

        master_data_module.entity(self.mapping_source_attribute) do |t|
          t.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)
          t.sync.synchronize = false
          t.string(:Code, 5, :primary_key => true)
        end unless master_data_module.entity_by_name?(self.mapping_source_attribute)

        master_data_module.service(:SyncTempPopulationService) do |s|
          s.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)
          if s.ejb?
            s.ejb.generate_boundary = false
            s.ejb.bind_in_tests = false
            s.ejb.generate_base_test = false
          end

          s.method(:PreSync) do |m|
            m.text(:MappingSourceCode)
          end
          s.method(:PostSync) do |m|
            m.text(:MappingSourceCode)
          end

          master_data_module.sync.entities_to_synchronize.collect do |entity|
            s.method("Count#{entity.qualified_name.gsub('.', '')}") do |m|
              m.text(:MappingSourceCode)
              m.returns(:integer)
            end
            s.method("Verify#{entity.qualified_name.gsub('.', '')}") do |m|
              m.text(:MappingSourceCode)
              m.parameter(:Recorder, 'iris.syncrecord.server.service.SynchronizationRecorder')
            end
            s.method("Populate#{entity.qualified_name.gsub('.', '')}") do |m|
              m.text(:MappingSourceCode)
              m.datetime(:At)
              m.parameter(:Recorder, 'iris.syncrecord.server.service.SynchronizationRecorder')
            end
            s.method("Reset#{entity.qualified_name.gsub('.', '')}") do |m|
              m.text(:MappingSourceCode)
              m.datetime(:At)
              m.parameter(:Recorder, 'iris.syncrecord.server.service.SynchronizationRecorder')
            end
            s.method("Finalize#{entity.qualified_name.gsub('.', '')}") do |m|
              m.text(:MappingSourceCode)
              m.datetime(:At)
              m.parameter(:Recorder, 'iris.syncrecord.server.service.SynchronizationRecorder')
            end
          end
        end unless master_data_module.service_by_name?(:SyncTempPopulationService)

        if self.sync_out_of_master?
          master_data_module.service(:SynchronizationService) do |s|
            s.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)
            s.ejb.generate_boundary = false if s.ejb?
            s.method(:SynchronizeDataSource) do |m|
              m.text(:MappingSourceCode)
              m.returns('iris.syncrecord.server.data_type.SyncStatusDTO')
            end
          end unless master_data_module.service_by_name?(:SynchronizationService)

          unless master_data_module.exception_by_name?(:BadSyncSequence)
            master_data_module.exception(:BadSyncSequence, 'java.exception_category' => :runtime) do |e|
              e.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)
            end
          end

          master_data_module.service(:SynchronizationContext) do |s|
            s.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)
            if s.ejb?
              s.ejb.generate_boundary = true
              s.ejb.generate_base_test = false
            end

            master_data_module.sync.entities_to_synchronize.each do |entity|
              s.method(:"Query#{entity.data_module.name}#{entity.name}Updates") do |m|
                m.text(:MappingSourceCode)
                m.returns('java.lang.Object[]', :collection_type => :sequence)
              end
              s.method(:"Query#{entity.data_module.name}#{entity.name}Removals") do |m|
                m.text(:MappingSourceCode)
                m.returns('java.lang.Object[]', :collection_type => :sequence)
              end

              s.method(:"CreateOrUpdate#{entity.data_module.name}#{entity.name}") do |m|
                m.text(:MappingSourceCode)
                m.parameter(:Record, 'java.lang.Object[]')
                m.returns(:boolean, :description => 'Return true on create, false on update')
              end
              s.method(:"Remove#{entity.data_module.name}#{entity.name}") do |m|
                m.integer(:MappingID)
                m.parameter(:ID, entity.primary_key.jpa.java_type(:boundary), :nullable => true)
                m.returns(:boolean, :description => 'Return true on removalfrom non-master, false if not required')
              end
              s.method(:"Mark#{entity.data_module.name}#{entity.name}RemovalsPreSync") do |m|
                m.text(:MappingSourceCode)
                m.returns(:integer, :description => 'The number of records changed')
              end

              if entity.sync.update_via_sync?
                # The following methods are an in progress implementation of bulk sync actions
                s.method(:"GetSqlToDirectlyUpdate#{entity.data_module.name}#{entity.name}") do |m|
                  m.text(:MappingSourceCode)
                  m.returns(:text)
                end
                s.method(:"GetSqlToMarkUpdated#{entity.data_module.name}#{entity.name}AsSynchronized") do |m|
                  m.text(:MappingSourceCode)
                  m.returns(:text)
                end
              end
              s.method(:"GetSqlToDirectlyDelete#{entity.data_module.name}#{entity.name}") do |m|
                m.text(:MappingSourceCode)
                m.returns(:text)
              end
              s.method(:"GetSqlToMarkDeleted#{entity.data_module.name}#{entity.name}AsSynchronized") do |m|
                m.text(:MappingSourceCode)
                m.returns(:text)
              end
            end
          end unless master_data_module.service_by_name?(:SynchronizationContext)
        end
      end
    end

    facet.enhance(DataModule) do
      def transaction_time=(transaction_time)
        @transaction_time = transaction_time
      end

      def transaction_time?
        @transaction_time.nil? ? data_module.repository.sync.transaction_time? : !!@transaction_time
      end


      include Domgen::Java::BaseJavaGenerator
      include Domgen::Java::EEClientServerJavaPackage

      # Artifacts to sync out of Master
      java_artifact :sync_ejb, :service, :server, :sync, 'SynchronizationService#{data_module.repository.ejb.implementation_suffix}'
      java_artifact :sync_service_test, :service, :server, :sync, 'AbstractExtendedSynchronizationService#{data_module.repository.ejb.implementation_suffix}Test'
      java_artifact :sync_context_impl, :service, :server, :sync, 'AbstractSynchronizationContext'

      # Artifacts to sync into Master
      java_artifact :sync_temp_factory, :service, :server, :sync, 'SyncTempFactory'
      java_artifact :abstract_master_sync_ejb, :service, :server, :sync, 'AbstractMasterSyncService#{data_module.repository.ejb.implementation_suffix}'
      java_artifact :abstract_sync_temp_population_impl, :service, :server, :sync, 'AbstractSyncTempPopulationService#{data_module.repository.ejb.implementation_suffix}'
      java_artifact :master_sync_service_test, :service, :server, :sync, 'AbstractMasterSyncService#{data_module.repository.ejb.implementation_suffix}Test'

      def entities_to_synchronize
        raise 'entities_to_synchronize invoked when not master_data_module' unless master_data_module?
        data_module.repository.data_modules.select { |d| d.sync? }.collect do |dm|
          dm.entities.select { |e| e.concrete? && e.sync? && e.sync.synchronize? }
        end.flatten
      end

      def master_data_module?
        data_module.repository.sync.master_data_module == data_module.name
      end

      def sync_temp_data_module?
        data_module.repository.sync.sync_temp_data_module == data_module.name
      end

      def entity_prefix=(entity_prefix)
        raise "Can not set entity_prefix on #{data_module.name} as it is the master data_module" if master_data_module?
        raise "Can not set entity_prefix on #{data_module.name} as it is the sync_temp data_module" if sync_temp_data_module?
        @entity_prefix = entity_prefix
      end

      def entity_prefix
        raise "Attempted to invoke entity_prefix on #{data_module.name}, but not valid as it is the master data_module" if master_data_module?
        raise "Attempted to invoke entity_prefix on #{data_module.name}, but not valid as it is the sync_temp data_module" if sync_temp_data_module?
        @entity_prefix || ''
      end
    end

    facet.enhance(Attribute) do
      def custom_transform?
        @custom_transform.nil? ? false : !!@custom_transform
      end

      def custom_transform=(custom_transform)
        @custom_transform = custom_transform
      end

      def manual_sync=(manual_sync)
        raise "Attempted to invoke manual_sync= on #{attribute.qualified_name}, but not valid as it is not a reference" unless attribute.reference?
        @manual_sync = !!manual_sync
      end

      def manual_sync?
        @manual_sync.nil? ? false : @manual_sync
      end
    end

    facet.enhance(Entity) do
      def core_entity=(core_entity)
        @core_entity = core_entity
      end

      def core_entity
        raise "Attempted to invoke core_entity on entity #{entity.qualified_name} when not a master entity" unless core_entity?
        @core_entity
      end

      def core_entity?
        !@core_entity.nil?
      end

      def master_entity=(master_entity)
        @master_entity = master_entity
      end

      def master_entity
        raise "Attempted to invoke master_entity on entity #{entity.qualified_name} when not synchronizing entity" unless synchronize?
        @master_entity
      end

      def core?
        !self.master? && !self.sync_temp?
      end

      def master?
        self.core_entity?
      end

      def transaction_time=(transaction_time)
        @transaction_time = transaction_time
      end

      def transaction_time?
        @transaction_time.nil? ? entity.data_module.sync.transaction_time? : !!@transaction_time
      end

      def references_requiring_manual_sync
        entity.referencing_attributes.select { |a| (!a.sync? || a.sync.manual_sync?) && a.referenced_entity.sql? }
      end

      def references_not_requiring_manual_sync
        entity.referencing_attributes.select { |a| !a.set_once? && !a.immutable? && a.sync? && a.entity.sync.core? && !a.sync.manual_sync? && a.referenced_entity.sql? }
      end

      attr_writer :recursive

      # Is the entity recursive?
      # i.e. Do the sync operations need to repeat until 0 actions
      def recursive?
        @recursive.nil? ? (entity.sync.attributes_to_synchronize.any? { |a| a.reference? && a.referenced_entity.name == entity.sync.master_entity.name }) : !!@recursive
      end

      def sync_temp_entity=(sync_temp_entity)
        @sync_temp_entity = sync_temp_entity
      end

      def sync_temp_entity
        raise "Attempted to invoke sync_temp_entity on entity #{entity.qualified_name} when not synchronizing entity" unless synchronize?
        @sync_temp_entity
      end

      def sync_temp=(sync_temp)
        @sync_temp = sync_temp
      end

      def sync_temp?
        @sync_temp.nil? ? false : @sync_temp
      end

      def synchronize=(synchronize)
        raise "Attempted to synchronize master entity #{entity.qualified_name}" if master? && synchronize
        raise "Attempted to synchronize sync_temp entity #{entity.qualified_name}" if sync_temp? && synchronize
        @synchronize = synchronize
      end

      def synchronize?
        !master? && !sync_temp? && @synchronize.nil? ? true : @synchronize
      end

      def entity_prefix=(entity_prefix)
        @entity_prefix = entity_prefix
      end

      def entity_prefix
        @entity_prefix || entity.data_module.sync.entity_prefix
      end

      def attributes_to_synchronize
        entity.sync.master_entity.attributes.select do |a|
          a.sync? && !a.primary_key? && ![:MasterSynchronized, :CreatedAt, :DeletedAt].include?(a.name) &&
            !(a.reference? && !a.referenced_entity.sync.master?)
        end
      end

      def attributes_to_update
        attributes_to_synchronize.select { |a| !a.immutable? }
      end

      def update_via_sync?
        entity.attributes.select do |a|
          a.sync? &&
            !a.primary_key? &&
            !a.immutable? &&
            ![:MasterSynchronized, :CreatedAt, :DeletedAt].include?(a.name) &&
            !(a.reference? && a.referenced_entity.sync? && a.referenced_entity.sync.synchronize?)
        end.size > 0
      end

      def master_data_module
        entity.data_module.repository.sync.master_data_module
      end

      def sync_temp_data_module
        entity.data_module.repository.sync.sync_temp_data_module
      end

      def pre_complete
        return unless synchronize?

        if entity.sync.transaction_time?
          self.entity.datetime(:CreatedAt, :immutable => true) unless entity.attribute_by_name?(:CreatedAt)
          self.entity.datetime(:DeletedAt, :set_once => true, :nullable => true) unless entity.attribute_by_name?(:DeletedAt)
          self.entity.jpa.default_jpql_criterion = 'O.deletedAt IS NULL'

          self.entity.unique_constraints.each do |constraint|
            # Force the creation of the index with filter specified. Parallels behavious in sql facet.
            index = self.entity.sql.index(constraint.attribute_names, :unique => true)
            index.filter = "#{self.entity.sql.dialect.quote(:DeletedAt)} IS NULL"
          end
        end
        self.entity.jpa.detachable = true if self.entity.jpa?

        master_data_module = entity.data_module.repository.data_module_by_name(entity.data_module.repository.sync.master_data_module)
        master_data_module.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)

        sync_temp_data_module = entity.data_module.repository.data_module_by_name(entity.data_module.repository.sync.sync_temp_data_module)
        sync_temp_data_module.disable_facets_not_in(Domgen::Sync::VALID_SYNC_TEMP_FACETS)

        sync_temp_data_module.entity("#{self.entity.sync.entity_prefix}#{self.entity.name}") do |e|
          e.disable_facets_not_in(Domgen::Sync::VALID_SYNC_TEMP_FACETS)

          self.entity.sync.sync_temp_entity = e
          e.sync.sync_temp = true
          e.abstract = self.entity.abstract?
          e.final = self.entity.final?
          e.extends = self.entity.extends

          if self.entity.extends.nil?
            e.integer(:SyncTempID,
                      :primary_key => true,
                      :generated_value => true,
                      'sql.generator_type' => :sequence,
                      'sql.sequence_name' => "#{sql_name(:table, self.entity.name)}Seq")

            e.reference("#{self.master_data_module}.#{self.entity.data_module.repository.sync.mapping_source_attribute}", :name => :MappingSource, 'sql.column_name' => 'MappingSource', :description => 'A reference for originating system')
            e.string(:MappingKey, 255, :immutable => true, :description => 'Change to cause an instance with the same MappingID and MappingSource, to be recreated in Master.')
            e.string(:MappingID, 50, :description => 'The ID of entity in originating system')
          end

          self.entity.attributes.select { |a| !a.inherited? }.each do |a|
            next if a.primary_key?
            next if [:CreatedAt, :DeletedAt].include?(a.name)
            next unless a.sync?

            Domgen.error("Can not yet synchronize entity structs as in #{a.qualified_name}") if a.struct?

            name = a.name
            attribute_type = a.attribute_type

            options = {}

            options[:collection_type] = a.collection_type
            options[:nullable] = a.nullable?

            if a.reference?
              attribute_type = :text
              name = "#{name}MappingID"
              options[:length] = 50
            elsif a.enumeration?
              options[:enumeration] = a.enumeration
              options[:length] = a.length if a.enumeration.textual_values?
            elsif a.text?
              options[:length] = a.length
              options[:min_length] = a.min_length
              options[:allow_blank] = a.allow_blank?
            end
            options[:abstract] = a.abstract?

            e.attribute(name, attribute_type, options)

            if a.reference?
              filter = a.nullable? ? "#{e.attribute_by_name(name).sql.quoted_column_name} IS NOT NULL" : nil
              e.sql.index([:MappingSource, name], :filter => filter, :include_attribute_names => [:MappingKey, :MappingID])
            end
          end
        end

        master_data_module.entity("#{self.entity.sync.entity_prefix}#{self.entity.name}") do |e|
          e.disable_facets_not_in(Domgen::Sync::VALID_MASTER_FACETS)

          self.entity.sync.master_entity = e
          e.sync.core_entity = self
          e.sync.transaction_time = self.entity.sync.transaction_time?
          e.abstract = self.entity.abstract?
          e.final = self.entity.final?
          e.extends = self.entity.extends

          if self.entity.extends.nil?
            e.integer(:ID,
                      :primary_key => true,
                      :generated_value => true,
                      'sql.generator_type' => :sequence,
                      'sql.sequence_name' => "#{sql_name(:table, self.entity.name)}Seq")

            e.reference(self.entity.data_module.repository.sync.mapping_source_attribute, :name => :MappingSource, :immutable => true, 'sql.column_name' => 'MappingSource', :description => 'A reference for originating system')
            e.string(:MappingKey, 255, :immutable => true, :description => 'Uniquely defines an instance with same MappingID and MappingSource.')
            e.string(:MappingID, 50, :immutable => true, :description => 'The ID of entity in originating system')
            e.boolean(:MasterSynchronized, :description => 'Set to true if synchronized from master tables into the main data area')

            e.sql.index([:MappingID, :MappingKey, :MappingSource], :unique => true, :filter => "#{e.sql.dialect.quote(:DeletedAt)} IS NULL")
            e.sql.index([:MappingSource, :MappingID], :include_attribute_names => [:ID], :filter => "#{e.sql.dialect.quote(:DeletedAt)} IS NULL")
          end

          self.entity.attributes.select { |a| !a.inherited? || a.primary_key? }.each do |a|
            next unless a.sync?

            # For self referential, non-transaction time entities, we have to set sql.on_delete
            # attribute otherwise sync will fail to remove the entity during synchronization
            if a.reference? && a.referenced_entity.qualified_name == a.entity.qualified_name && !entity.sync.transaction_time?
              a.sql.on_delete = :set_null
            end

            options = {}
            Domgen.error("Can not yet synchronize entity structs as in #{a.qualified_name}") if a.struct?
            options[:referenced_entity] = a.referenced_entity.name if a.reference?
            name = a.name
            attribute_type = a.attribute_type

            if a.primary_key?
              name = a.entity.root_entity.name
              attribute_type = :reference
              options[:referenced_entity] = a.entity.qualified_name
              options[:nullable] = true
              options['sql.on_delete'] = :set_null
              options['inverse.multiplicity'] = :zero_or_one
              options['jpa.persistent'] = true
              options[:abstract] = a.entity.abstract?
              options[:override] = !a.entity.extends.nil?
            else
              options[:abstract] = a.abstract?
            end

            if a.enumeration?
              options[:enumeration] = a.enumeration
              options[:length] = a.length if a.enumeration.textual_values?
            end
            if a.text?
              options[:length] = a.length
              options[:min_length] = a.min_length
              options[:allow_blank] = a.allow_blank?
            end
            options[:collection_type] = a.collection_type
            options[:nullable] = a.nullable? || a.primary_key?
            options[:immutable] = !a.primary_key? && a.immutable?
            options[:set_once] = a.set_once?

            # We can not guarantee that fields will be unique as the ordering of
            # updates in the synchronization process will not guarantee this condition.
            # However we generate checks in sync code so this should never happen.
            # However we can get problems synchronizing from Master into non-Master tables
            # as ordering can still lead to uniqueness constraints being violated during
            # the sync process and aborting the sync action. However sync_ejb.java.erb will
            # continue synchronization for all entities in a type so that hopefully the next
            # synchronization will allow all entities to flow through. This will not work if
            # entities have multiple unique fields and there is no ordering of operations that
            # will allow it to proceed. In this case, administrator intervention is required.
            options[:unique] = false

            e.attribute(name, attribute_type, options)

            if a.primary_key?
              e.sql.index([name], :unique => true, :filter => "#{e.attribute_by_name(name).sql.quoted_column_name} IS NOT NULL")
            end

            if a.reference?
              # Create an index to speed up validity checking when column is sparsely populated
              prefix = a.nullable? ? "#{e.attribute_by_name(name).sql.quoted_column_name} IS NOT NULL AND " : ''
              e.sql.index([name], :filter => "#{prefix}#{e.sql.dialect.quote(:DeletedAt)} IS NULL", :include_attribute_names => [:MappingKey, :MappingID])
            end

            if a.unique?
              # If entity is a transaction time entity, and an uniqueness index that filters out logically deleted entities
              if entity.sync.transaction_time?
                existing_constraint = self.entity.unique_constraints.find do |uq|
                  uq.attribute_names.length == 1 && uq.attribute_names[0].to_s == a.name.to_s
                end
                if existing_constraint.nil?
                  self.entity.sql.index([a.name], :unique => true, :filter => "#{e.sql.dialect.quote(:DeletedAt)} IS NULL")
                end
              end
            end
          end

          # update indexes in the original entity, if it is a transaction time entity so filtering can be specified
          if entity.sync.transaction_time?
            self.entity.sql.indexes.each do |index|
              next if index.cluster?

              unless index.attribute_names.include?(:DeletedAt) || index.attribute_names.include?(:CreatedAt)
                unless index.filter && (index.filter =~ Regexp.new(Regexp.escape(e.sql.dialect.quote(:DeletedAt))) || index.filter =~ Regexp.new(Regexp.escape(e.sql.dialect.quote(:CreatedAt))))
                  index.filter = (index.filter.nil? ? '' : "(#{index.filter}) AND ") + "#{entity.sql.dialect.quote(:DeletedAt)} IS NULL"
                end
              end
            end

            entity.sync.references_not_requiring_manual_sync.each do |a|
              a.entity.query("FindAllBy#{a.name}") unless a.entity.query_by_name?("FindAllBy#{a.name}")
            end
          end

          unless entity.sync.transaction_time?
            e.datetime(:CreatedAt, :immutable => true) unless e.attribute_by_name?(:CreatedAt)
            e.datetime(:DeletedAt, :set_once => true, :nullable => true) unless e.attribute_by_name?(:DeletedAt)
          end

          if e.concrete?
            e.query(:FindByMappingSourceAndMappingID)
            e.query(:FindUndeletedByMappingSourceAndMappingID,
                    'jpa.standard_query' => true,
                    'jpa.jpql' => 'O.mappingSource = :MappingSource AND O.mappingID = :MappingID and O.deletedAt IS NULL')
            e.query(:GetByMappingSourceAndMappingID)
            e.jpa.test_create_default(e.root_entity.name => 'null', :MasterSynchronized => 'false', :CreatedAt => 'new java.util.Date()', :DeletedAt => 'null')
            e.jpa.test_create_default(e.root_entity.name => 'null', :MasterSynchronized => 'false', :MappingKey => 'mappingID', :CreatedAt => 'new java.util.Date()', :DeletedAt => 'null')
            e.jpa.test_create_default(e.root_entity.name => 'null', :MasterSynchronized => 'false', :MappingKey => 'mappingID')
            e.jpa.test_create_default(e.root_entity.name => 'null', :MasterSynchronized => 'false')
            e.jpa.test_create_default(:CreatedAt => 'new java.util.Date()', :DeletedAt => 'null')
            e.jpa.test_update_default({e.root_entity.name => nil, :MasterSynchronized => 'false', :MappingSource => nil, :MappingKey => nil, :MappingID => nil, :CreatedAt => nil, :DeletedAt => nil}, :force_refresh => true)
            e.jpa.test_update_default({e.root_entity.name => nil, :MasterSynchronized => 'false', :MappingSource => nil, :MappingKey => nil, :MappingID => nil}, :force_refresh => true)
            e.jpa.test_update_default({:CreatedAt => nil, :DeletedAt => nil}, :force_refresh => true)
            delete_defaults = {}
            e.attributes.each do |a|
              delete_defaults[a.name] = nil unless a.generated_value? || a.immutable? || !a.jpa?
            end
            delete_defaults[:MasterSynchronized] = 'false'
            delete_defaults[:DeletedAt] = 'new java.util.Date()'
            e.jpa.test_update_default(delete_defaults, :force_refresh => true, :factory_method_name => "mark#{e.name}AsDeleted")
            e.query(:CountByMappingSource)
            e.query(:CountUnsynchronizedByMappingSource,
                    'jpa.standard_query' => true,
                    'jpa.jpql' => 'O.mappingSource = :MappingSource AND O.masterSynchronized = false')

            if entity.sync.transaction_time?
              entity.jpa.create_default(:CreatedAt => 'new java.util.Date()', :DeletedAt => 'null')
              entity.jpa.update_default(:DeletedAt => nil)
              entity.jpa.update_defaults.each do |defaults|
                entity.jpa.update_default(defaults.values.merge(:DeletedAt => nil)) do |new_default|
                  new_default.factory_method_name = defaults.factory_method_name
                end
                entity.jpa.remove_update_default(defaults)
              end
              if entity.imit?
                attributes = entity.attributes.select { |a| %w(CreatedAt DeletedAt).include?(a.name.to_s) && a.imit? }.collect { |a| a.name.to_s }
                if attributes.size > 0
                  defaults = {}
                  defaults[:CreatedAt] = 'new java.util.Date()' if attributes.include?('CreatedAt')
                  defaults[:DeletedAt] = 'null' if attributes.include?('DeletedAt')
                  entity.imit.test_create_default(defaults)
                end
              end
            end
          end
        end
      end
    end
  end
end
