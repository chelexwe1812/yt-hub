//
//  YT_musicTests.swift
//  YT musicTests
//
//  Created by Marcelo on 4/8/26.
//

import Testing
import Foundation
@testable import YT_music

struct YT_musicTests {

    // MARK: - ServiceMode: URLs

    @Test func musicModePointsToYouTubeMusic() {
        #expect(ServiceMode.music.url.absoluteString == "https://music.youtube.com")
    }

    @Test func videosModePointsToYouTube() {
        #expect(ServiceMode.videos.url.absoluteString == "https://www.youtube.com")
    }

    @Test func allModeURLsUseHTTPS() {
        for mode in ServiceMode.allCases {
            #expect(mode.url.scheme == "https")
        }
    }

    // MARK: - ServiceMode: labels e identidad

    @Test func labelsMatchExpectedText() {
        #expect(ServiceMode.music.label == "Music")
        #expect(ServiceMode.videos.label == "Youtube")
    }

    @Test func idMatchesRawValue() {
        #expect(ServiceMode.music.id == "music")
        #expect(ServiceMode.videos.id == "videos")
    }

    // MARK: - ServiceMode: casos

    @Test func allCasesContainsBothModesInOrder() {
        #expect(ServiceMode.allCases == [.music, .videos])
    }

    @Test func rawValueRoundTrips() {
        #expect(ServiceMode(rawValue: "music") == .music)
        #expect(ServiceMode(rawValue: "videos") == .videos)
        #expect(ServiceMode(rawValue: "otra") == nil)
    }
}
