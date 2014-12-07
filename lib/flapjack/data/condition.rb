# !/usr/bin/env ruby

require 'sandstorm/records/redis_record'

module Flapjack
  module Data
    class Condition

      # constants, existence of which will be checked on startup; this may
      # be made more configurable at a later date
      HEALTHY   = {1 => 'ok'}

      UNHEALTHY = {3 => 'critical',
                   2 => 'warning',
                   1 => 'unknown'}

      include Sandstorm::Records::RedisRecord

      define_attributes :name      => :string,
                        :healthy   => :boolean,
                        :priority  => :integer

      unique_index_by :name
      index_by :healthy, :priority

      has_and_belongs_to_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :condition

      # can't use before_validation, as the id's autogenerated by then
      alias_method :original_save, :save
      def save
        self.id = self.name if self.id.nil?
        original_save
      end

      # name must == id
      validates :name, :presence => true,
        :inclusion => { :in => proc {|t| [t.id] }},
        :format => /\A[a-z0-9\-_]+\z/i

      before_update :update_allowed?
      def update_allowed?
        !self.changed.include?('name')
      end

      def self.jsonapi_id
        :name
      end

      def self.jsonapi_attributes
        [:name]
      end

      def self.jsonapi_singular_associations
        []
      end

      def self.jsonapi_multiple_associations
        []
      end
    end
  end
end