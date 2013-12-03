module Riak
  class Client
    class BeefcakeProtobuffsBackend
      def crdt_operator
        return CrdtOperator.new self
      end
      
      class CrdtOperator
        include Util::Translation

        attr_reader :backend
        
        def initialize(backend)
          @backend = backend
        end

        def operate(bucket, key, bucket_type, operation, options={})
          serialized = serialize(operation)
          args = {
            bucket: bucket,
            key: key,
            type: bucket_type,
            op: serialized
          }.merge options
          request = DtUpdateReq.new args
          
          backend.write_protobuff :DtUpdateReq, request

          response = decode
        end
        
        def serialize(operation)
          case operation.type
          when :counter
            serialize_counter operation
          when :set
            serialize_set operation
          when :map
            serialize_map operation
          else
            raise ArgumentError, t('crdt.unknown_field', symbol: operation.type.inspect)
          end
        end

        private

        def decode
          header = socket.read 5

          if header.nil?
            backend.teardown
            raise SocketError, t('pbc.unexpected_eof')
          end

          msglen, msgcode = header.unpack 'NC'

          if BeefcakeProtobuffsBackend::MESSAGE_CODES[msgcode] != :DtUpdateResp
            backend.teardown
            raise SocketError, t('pbc.wanted_dt_update_resp')
          end

          message = socket.read(msglen - 1)

          DtUpdateResp.decode message
        end

        def socket
          backend.socket
        end
        
        def inner_serialize(operation)
          case operation.type
          when :counter
            serialize_inner_counter operation
          when :flag
            serialize_flag operation
          when :register
            serialize_register operation
          when :set
            serialize_inner_set operation
          when :map
            serialize_inner_map operation
          else
            raise ArgumentError, t('crdt.unknown_inner_field', symbol: operation.type.inspect)
          end
        end
        
        def serialize_counter(counter_op)
          DtOp.new(
                   counter_op: CounterOp.new(
                                             increment: counter_op.value
                                             )
                   )
        end

        def serialize_inner_counter(counter_op)
          MapUpdate.new(
                        field: MapField.new(
                                            name: counter_op.name,
                                            type: MapField::MapFieldType::COUNTER
                                            ),
                        counter_op: CounterOp.new(
                                                  increment: counter_op.value
                                                  )
                        )
        end

        def serialize_flag(flag_op)
          operation_value = flag_op ? MapUpdate::FlagOp::ENABLE : MapUpdate::FlagOp::DISABLE
          MapUpdate.new(
                        field: MapField.new(
                                            name: flag_op.name,
                                            type: MapField::MapFieldType::FLAG
                                            ),
                        flag_op: operation_value
                        )
        end

        def serialize_register(register_op)
          MapUpdate.new(
                        field: MapField.new(
                                            name: register_op.name,
                                            type: MapField::MapFieldType::REGISTER
                                            ),
                        register_op: register_op.value
                        )
        end

        def serialize_set(set_op)
          value = set_op.value or nil
          
          DtOp.new(
                   set_op: SetOp.new(
                                     adds: value[:add],
                                     removes: value[:remove]
                                     )
                   )
        end

        def serialize_inner_set(set_op)
          value = set_op.value or nil

          MapUpdate.new(
                        field: MapField.new(
                                            name: set_op.name,
                                            type: MapField::MapFieldType::SET
                                            ),
                        set_op: SetOp.new(
                                          adds: value[:add],
                                          removes: value[:remove]
                                          )
                        )
        end

        def serialize_map(map_op)
          inner_op = map_op.value
          inner_serialized = inner_serialize inner_op

          DtOp.new(
                   map_op: MapOp.new(
                                     updates: [inner_serialized]
                                     )
                   )
        end

        def serialize_inner_map(map_op)
          inner_op = map_op.value
          inner_serialized = inner_serialize inner_op

          MapUpdate.new(
                        field: MapField.new(
                                            name: map_op.name,
                                            type: MapField::MapFieldType::MAP
                                            ),
                        map_op: MapOp.new(
                                          updates: [inner_serialized]
                                     ))
        end
      end
    end
  end
end
