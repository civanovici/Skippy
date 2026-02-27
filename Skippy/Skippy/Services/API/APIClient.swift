import Foundation

protocol APIClientProtocol {
    var audiobookshelf: AudiobookshelfAPI { get }
}

struct APIClient: APIClientProtocol {
    let audiobookshelf: AudiobookshelfAPI

    init(audiobookshelf: AudiobookshelfAPI = MockAudiobookshelfAPI()) {
        self.audiobookshelf = audiobookshelf
    }
}
