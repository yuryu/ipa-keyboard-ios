//
//  ContentView.swift
//  IPAKeyboard
//
//  Created by Emma Haruka Iwao on 6/28/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("content-view-globe-image")
            Text("Hello, world!")
                .accessibilityIdentifier("content-view-hello-world-label")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
