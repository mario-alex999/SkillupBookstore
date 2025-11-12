use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Default, PartialEq, starknet::Store)]
pub struct Book {
    pub id: u8,
    pub title: felt252,
    pub author: felt252,
    pub price: u64,
    pub stock: u64,
}

#[starknet::interface]
pub trait IBookStore<TContractstate> {
    fn add_book(ref self: TContractstate, title: felt252, author: felt252, price: u64, stock: u64);
    fn remove_book(ref self: TContractstate, id: u8);
    fn borrow_book(ref self: TContractstate, id: u8);
    fn return_book(ref self: TContractstate, id: u8);
    fn get_books(self: @TContractstate) -> Array<Book>;
    fn get_book(self: @TContractstate, id: u8) -> Book;
    fn buy_book(ref self: TContractstate, id: u8);
    fn refund_book(ref self: TContractstate, id: u8);
    fn get_refunded_books(self: @TContractstate, buyer: ContractAddress) -> Book;
}

#[starknet::contract]
pub mod SkillupBookStore {
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{Book, IBookStore};

    #[storage]
    pub struct Storage {
        pub storekeeper: ContractAddress,
        pub books: Map<u8, Book>,
        pub lent_books: Map<ContractAddress, Book>,
        pub bought_books: Map<ContractAddress, Book>,
        pub refunded_books: Map<ContractAddress, Book>,
        pub sales_record: Map<u8, u8>,
        pub refunds_record: Map<ContractAddress, Book>,
        pub book_counter: u8 //initialize with 1, start the ids of the book from 1
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BookBorrowed: BookBorrowed,
        BookReturned: BookReturned,
        BookAdded: BookAdded,
        RemovedBook: RemovedBook,
        BoughtBook: BoughtBook,
        RefundedBook: RefundedBook,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookBorrowed {
        book_id: u8,
        borrower: ContractAddress,
        timestap: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookReturned {
        pub book_id: u8,
        pub borrower: ContractAddress,
        pub timestap: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookAdded {
        book_id: u8,
        book_title: felt252,
        book_author: felt252,
        timestap: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RemovedBook {
        pub book_id: u8,
        pub timestap: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BoughtBook {
        pub book_id: u8,
        pub buyer: ContractAddress,
        pub quantity: u64,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RefundedBook {
        pub book_id: u8,
        pub buyer: ContractAddress,
        pub quantity: u64,
        pub timestamp: u64,
    }


    #[constructor]
    fn constructor(ref self: ContractState, storekepper: ContractAddress) {
        self.storekeeper.write(storekepper);
        self.book_counter.write(1);
    }

    #[abi(embed_v0)]
    pub impl SkillupBookStoreImpl of IBookStore<ContractState> {
        fn add_book(
            ref self: ContractState, title: felt252, author: felt252, price: u64, stock: u64,
        ) {
            let caller: ContractAddress = get_caller_address();
            let storekepper = self.storekeeper.read();
            assert(caller == storekepper, 'Caller not permitted');

            let book_id = self.book_counter.read();
            self.book_counter.write(book_id + 1);

            let book = Book { id: book_id, title, author, price, stock };

            self.books.entry(book_id).write(book);

            let _timestamp = get_block_timestamp();

            self
                .emit(
                    BookAdded {
                        book_id,
                        book_title: title,
                        book_author: author,
                        timestap: get_block_timestamp(),
                    },
                )
        }
        fn remove_book(ref self: ContractState, id: u8) {
            assert(get_caller_address() == self.storekeeper.read(), 'Caller not permitted');
            let existing_books = self.books.entry(id).read();

            assert(existing_books != Default::default(), 'Book does not exist');

            self.books.entry(id).write(Default::default());
            self.emit(RemovedBook { book_id: id, timestap: get_block_timestamp() })
        }
        fn borrow_book(ref self: ContractState, id: u8) {
            let caller = get_caller_address();

            let already_borrowed_book = self.lent_books.entry(caller).read();
            assert(already_borrowed_book == Default::default(), 'Caller holds a book already');

            let existing_books = self.books.entry(id).read();
            assert(existing_books != Default::default(), 'Book does not exist');

            self.lent_books.entry(caller).write(existing_books);

            self
                .emit(
                    BookBorrowed { book_id: id, borrower: caller, timestap: get_block_timestamp() },
                )
        }
        fn return_book(ref self: ContractState, id: u8) {
            let caller = get_caller_address();

            let borrowed_book = self.lent_books.entry(caller).read();
            let the_book = self.books.entry(id).read();
            assert(the_book == borrowed_book, 'Returning wrong book');

            assert(borrowed_book != Default::default(), 'Caller did not borrow a book');

            self.lent_books.entry(caller).write(Default::default());

            self
                .emit(
                    BookReturned { book_id: id, borrower: caller, timestap: get_block_timestamp() },
                )
        }
        fn get_books(self: @ContractState) -> Array<Book> {
            let mut all_books_arrary = array![];
            let book_counter = self.book_counter.read();

            for i in 1..book_counter {
                let current_book = self.books.entry(i).read();
                all_books_arrary.append(current_book);
            }

            all_books_arrary
        }
        fn get_book(self: @ContractState, id: u8) -> Book {
            let existing_book = self.books.entry(id).read();
            assert(existing_book != Default::default(), 'Book does not exist');
            existing_book
        }
        fn buy_book(ref self: ContractState, id: u8) {
            let buyer: ContractAddress = get_caller_address();

            let existing_book = self.books.entry(id).read();
            assert(existing_book != Default::default(), 'Book does not exist');

            // record the purchase for the buyer
            self.bought_books.entry(buyer).write(existing_book);

            // increment sales record
            let sales = self.sales_record.entry(id).read();
            self.sales_record.entry(id).write(sales + 1);

            self
                .emit(
                    BoughtBook {
                        book_id: id, buyer, quantity: 1, timestamp: get_block_timestamp(),
                    },
                )
        }
        fn refund_book(ref self: ContractState, id: u8) {
            let caller = get_caller_address();

            // read the buyer's purchased book record
            let purchased_book = self.bought_books.entry(caller).read();
            let the_book = self.books.entry(id).read();
            assert(the_book == purchased_book, 'Refunding wrong book');

            assert(purchased_book != Default::default(), 'Caller did not buy this book');

            // remove the purchase record
            self.bought_books.entry(caller).write(Default::default());

            // record the refund for the buyer
            self.refunded_books.entry(caller).write(the_book);

            // decrement sales record
            let sales = self.sales_record.entry(id).read();
            self.sales_record.entry(id).write(sales - 1);

            self
                .emit(
                    RefundedBook {
                        book_id: id, buyer: caller, quantity: 1, timestamp: get_block_timestamp(),
                    },
                )
        }
        fn get_refunded_books(self: @ContractState, buyer: ContractAddress) -> Book {
            let existing_book = self.refunded_books.entry(buyer).read();
            assert(existing_book != Default::default(), 'No refunded books found');

            existing_book
        }
    }
}
