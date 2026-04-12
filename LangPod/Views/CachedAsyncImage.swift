import SwiftUI

/// Drop-in replacement for AsyncImage backed by ImageCache (memory + disk).
struct CachedAsyncImage<Placeholder: View>: View {
    let url: String
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = await ImageCache.shared.image(for: url)
        }
    }
}
