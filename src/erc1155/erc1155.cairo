#[abi]
trait ERC1155ABI {
}

#[contract]
mod ERC1155 {
  use array::{ Span, ArrayTrait, SpanTrait, ArrayDrop };
  use option::OptionTrait;
  use traits::Into;
  use traits::TryInto;
  use zeroable::Zeroable;
  use starknet::contract_address::ContractAddressZeroable;

  use erc1155::utils::serde::SpanSerde;
  use erc1155::introspection::erc165::ERC165;
  use erc1155::erc1155::interface::IERC1155ReceiverDispatcher;
  use erc1155::erc1155::interface::IERC1155ReceiverDispatcherTrait;
  use erc1155::introspection::erc165::IERC165Dispatcher;
  use erc1155::introspection::erc165::IERC165DispatcherTrait;

  // Storage //

  struct Storage {
    _balances: LegacyMap<(u256, starknet::ContractAddress), u256>,
    _operator_approvals: LegacyMap<(starknet::ContractAddress, starknet::ContractAddress), bool>,
    _uri: LegacyMap<usize, felt252>,
  }

  // Events //

  // TODO: events

  // Init //

  #[constructor]
  fn constructor(uri_: Array<felt252>) {
    _set_URI(uri_.span());
  }

  // Getters //

  #[view]
  fn uri(tokenId: u256) -> Array<felt252> {
    let mut ret = ArrayTrait::<felt252>::new();
    let len: usize = _uri::read(0).try_into().unwrap();
    let mut i: usize = 1;

    loop {
      if (i > len) {
        break ();
      }

      ret.append(_uri::read(i));
      i = i + 1;
    };

    ret
  }

  // ERC165 //

  #[view]
  fn supports_interface(interface_id: u32) -> bool {
    ERC165::supports_interface(interface_id)
  }

  // Balance //

  #[view]
  fn balance_of(account: starknet::ContractAddress, id: u256) -> u256 {
    _balances::read((id, account))
  }

  #[view]
  fn balance_of_batch(accounts: Span<starknet::ContractAddress>, ids: Span<u256>) {
    // TODO
  }

  // Approval //

  #[external]
  fn set_approval_for_all(operator: starknet::ContractAddress, approved: bool) {
    let caller = starknet::get_caller_address();

    _set_approval_for_all(owner: caller, :operator, :approved);
  }

  #[view]
  fn is_approved_for_all(account: starknet::ContractAddress, operator: starknet::ContractAddress) -> bool {
    _operator_approvals::read((account, operator))
  }

  // Transfer //

  #[external]
  fn safe_transfer_from(
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    id: u256,
    amount: u256,
    data: Span<felt252>
  ) {
    let caller = starknet::get_caller_address();
    assert(from == caller, 'ERC1155: caller not allowed');
    assert(is_approved_for_all(account: from, operator: caller), 'ERC1155: caller not allowed');

    _safe_transfer_from(:from, :to, :id, :amount, :data);
  }

  #[external]
  fn safe_batch_transfer_from(
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    ids: Span<u256>,
    amounts: Span<u256>,
    data: Span<felt252>
  ) {
    let caller = starknet::get_caller_address();
    assert(from == caller, 'ERC1155: caller not allowed');
    assert(is_approved_for_all(account: from, operator: caller), 'ERC1155: caller not allowed');

    _safe_batch_transfer_from(:from, :to, :ids, :amounts, :data);
  }

  // Mint //

  // TODO: mint

  // Burn //

  // TODO: burn

  // Internals //

  // does not clean previous URI if previous len < new len
  #[internal]
  fn _set_URI(mut new_URI: Span<felt252>) {
    // store new len
    _uri::write(0, new_URI.len().into());

    let mut i: usize = 1;

    loop {
      match new_URI.pop_front() {
        Option::Some(word) => {
          _uri::write(i, *word);
          i = i + 1;
        },
        Option::None(_) => {
          break ();
        },
      };
    };
  }

  #[internal]
  fn _set_approval_for_all(owner: starknet::ContractAddress, operator: starknet::ContractAddress, approved: bool) {
    assert(owner != operator, 'ERC1155: cannot approve owner');

    _operator_approvals::write((owner, operator), approved)
  }

  #[internal]
  fn _update(
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    mut ids: Span<u256>,
    amounts: Span<u256>,
    data: Span<felt252>
  ) {
    assert(ids.len() == amounts.len(), 'ERC1155: bad ids & amounts lens');

    let operator = starknet::get_caller_address();

    let mut i: usize = 0;
    loop {
      if (ids.len() == i) {
        break ();
      }

      let id = *ids.at(i);
      let amount = *amounts.at(i);

      // Decrease sender balance
      if (from.is_non_zero()) {
        let from_balance = _balances::read((id, from));
        assert(from_balance >= amount, 'ERC1155: insufficient balance');

        _balances::write((id, from), from_balance - amount);
      }

      // Increase recipient balance
      if (to.is_non_zero()) {
        let to_balance = _balances::read((id, from));
        _balances::write((id, to), to_balance + amount);
      }

      i = i + 1;
    };

    // Safe transfer check
    if (ids.len() == 1) {
      let id = *ids.at(0);
      let amount = *amounts.at(0);

      if (to.is_non_zero()) {
        _do_safe_transfer_acceptance_check(:operator, :from, :to, :id, :amount, :data);
      }
    } else {
      if (to.is_non_zero()) {
        _do_safe_batch_transfer_acceptance_check(:operator, :from, :to, :ids, :amounts, :data);
      }
    }
  }

  #[internal]
  fn _safe_transfer_from(
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    id: u256,
    amount: u256,
    data: Span<felt252>
  ) {
    assert(to.is_non_zero(), 'ERC1155: transfer to 0 addr');
    assert(from.is_non_zero(), 'ERC1155: transfer from 0 addr');

    let ids = _as_singleton_span(id);
    let amounts = _as_singleton_span(amount);

    _update(:from, :to, :ids, :amounts, :data);
  }

  #[internal]
  fn _safe_batch_transfer_from(
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    ids: Span<u256>,
    amounts: Span<u256>,
    data: Span<felt252>
  ) {
    assert(to.is_non_zero(), 'ERC1155: transfer to 0 addr');
    assert(from.is_non_zero(), 'ERC1155: transfer from 0 addr');

    _update(:from, :to, :ids, :amounts, :data);
  }

  // safe transfer check //

  #[internal]
  fn _do_safe_transfer_acceptance_check(
    operator: starknet::ContractAddress,
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    id: u256,
    amount: u256,
    data: Span<felt252>
  ) {
    let ERC165 = IERC165Dispatcher { contract_address: to };

    if (ERC165.supports_interface(erc1155::erc1155::interface::IERC1155_RECEIVER_ID)) {
      // TODO: add casing fallback mechanism

      let ERC1155Receiver = IERC1155ReceiverDispatcher { contract_address: to };

      let response = ERC1155Receiver.on_erc1155_received(:operator, :from, :id, value: amount, :data);
      assert(response == erc1155::erc1155::interface::ON_ERC1155_RECEIVED_SELECTOR, 'ERC1155: safe transfer failed');
    } else {
      assert(
        ERC165.supports_interface(rules_account::account::interface::IACCOUNT_ID) == true,
        'ERC1155: safe transfer failed'
      );
    }
  }

  #[internal]
  fn _do_safe_batch_transfer_acceptance_check(
    operator: starknet::ContractAddress,
    from: starknet::ContractAddress,
    to: starknet::ContractAddress,
    ids: Span<u256>,
    amounts: Span<u256>,
    data: Span<felt252>
  ) {
    let ERC165 = IERC165Dispatcher { contract_address: to };

    if (ERC165.supports_interface(erc1155::erc1155::interface::IERC1155_RECEIVER_ID)) {
      // TODO: add casing fallback mechanism

      let ERC1155Receiver = IERC1155ReceiverDispatcher { contract_address: to };

      let response = ERC1155Receiver.on_erc1155_batch_received(:operator, :from, :ids, values: amounts, :data);
      assert(response == erc1155::erc1155::interface::ON_ERC1155_RECEIVED_SELECTOR, 'ERC1155: safe transfer failed');
    } else {
      assert(
        ERC165.supports_interface(rules_account::account::interface::IACCOUNT_ID) == true,
        'ERC1155: safe transfer failed'
      );
    }
  }

  // Utils //

  // TODO: make trait
  #[internal]
  fn _as_singleton_span(element: u256) -> Span<u256> {
    let mut arr = ArrayTrait::<u256>::new();
    arr.append(element);
    arr.span()
  }
}