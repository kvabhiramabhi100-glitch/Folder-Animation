import SwiftUI

@main
struct FolderStackApp: App {
    var body: some Scene {
        WindowGroup {
            FolderGalleryView(albums: Album.samples)
        }
    }
}
