import Foundation

struct BookDetailViewModel {
    let book: Audiobook

    var resumeChapter: Chapter? {
        book.chapters.first
    }
}
