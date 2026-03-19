# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class ListWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  class TestListService < ListWriteService
    attr_reader :hook_calls

    private

    def validate_changeset(renames:, deletes:, fail_validation: false, **)
      @hook_calls = [[:validate_changeset, { renames:, deletes: }]]
      fail_validation ? ['Forced validation error'] : []
    end

    def apply_renames(renames)
      (@hook_calls ||= []) << [:apply_renames, renames]
    end

    def apply_deletes(deletes)
      (@hook_calls ||= []) << [:apply_deletes, deletes]
    end

    def apply_ordering(**params)
      (@hook_calls ||= []) << [:apply_ordering, params]
    end
  end

  setup do
    setup_test_kitchen
  end

  test 'calls hooks in order within a transaction on success' do
    service = TestListService.new(kitchen: @kitchen)
    result = service.update(renames: { 'a' => 'b' }, deletes: ['c'])

    assert result.success
    assert_empty result.errors
    hooks = service.hook_calls.map(&:first)

    assert_equal %i[validate_changeset apply_renames apply_deletes apply_ordering], hooks
  end

  test 'short-circuits on validation errors without transaction or finalize' do
    assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
      service = TestListService.new(kitchen: @kitchen)
      result = service.update(renames: {}, deletes: [], fail_validation: true)

      assert_not result.success
      assert_equal ['Forced validation error'], result.errors
      assert_equal 1, service.hook_calls.size
    end
  end

  test 'normalizes nil renames to empty hash' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: nil, deletes: [])

    assert_empty service.hook_calls.first[1][:renames]
  end

  test 'normalizes nil deletes to empty array' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: {}, deletes: nil)

    assert_empty service.hook_calls.first[1][:deletes]
  end

  test 'class-level update delegates to instance' do
    result = TestListService.update(kitchen: @kitchen, renames: {}, deletes: [])

    assert result.success
  end

  test 'passes extra keyword arguments through to hooks' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: {}, deletes: [], fail_validation: false)

    last_hook = service.hook_calls.last

    assert_equal :apply_ordering, last_hook[0]
  end

  test 'finalize_writes broadcasts on success' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      TestListService.update(kitchen: @kitchen, renames: {}, deletes: [])
    end
  end

  # --- shared validation helpers ---

  test 'validate_order flags too many items' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[a b c], max_items: 2, max_name_length: 50)

    assert(errors.any? { |e| e.include?('Too many') })
  end

  test 'validate_order flags names exceeding max length' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, ['a' * 51], max_items: 100, max_name_length: 50)

    assert(errors.any? { |e| e.include?('too long') })
  end

  test 'validate_order flags case-insensitive duplicates' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo foo], max_items: 100, max_name_length: 50)

    assert(errors.any? { |e| e.include?('more than once') })
  end

  test 'validate_order with exact_dupes false ignores exact duplicates' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo Foo], max_items: 100, max_name_length: 50, exact_dupes: false)

    assert_empty errors
  end

  test 'validate_order with exact_dupes false flags mixed-case variants' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo foo], max_items: 100, max_name_length: 50, exact_dupes: false)

    assert(errors.any? { |e| e.include?('more than once') })
  end

  test 'validate_renames_length flags names exceeding max' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_renames_length, { 'old' => 'a' * 51 }, 50)

    assert(errors.any? { |e| e.include?('exceeds maximum length') })
  end

  test 'validate_renames_length passes names within limit' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_renames_length, { 'old' => 'a' * 50 }, 50)

    assert_empty errors
  end
end
