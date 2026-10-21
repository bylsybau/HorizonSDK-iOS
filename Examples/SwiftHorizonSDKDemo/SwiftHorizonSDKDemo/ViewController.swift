//
//  ViewController.swift
//  HorizonSDKSwiftSample
//
//  Created by Stelios Petrakis on 2/25/15.
//  Copyright (c) 2015 Horizon Video Technologies. All rights reserved.
//

import UIKit
import Photos
import HorizonSDK
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

class ViewController: UIViewController, HVTCameraDelegate {

    // MARK: - Properti galeri

    private var mediaContainer: UIView?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerEndObserver: NSObjectProtocol?
    private var galleryButton: UIButton!

    // MARK: - Properti kamera

    var camera: HVTCamera!

    @IBOutlet weak var preview: HVTView!
    @IBOutlet weak var recordButton: UIButton!

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupGalleryButton()

        recordButton.layer.cornerRadius = 30.0

        preview.fillMode = .aspectFill

        camera = HVTCamera()
        camera.add(preview)
        camera.delegate = self

        AVCaptureDevice.requestAccess(for: AVMediaType.video) { _ in
            AVCaptureDevice.requestAccess(for: AVMediaType.audio) { _ in
                DispatchQueue.main.async {
                    self.startCamera()
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Preview mengikuti orientasi antarmuka (iPad / rotasi layar)
        if let scene = view.window?.windowScene {
            camera.interfaceOrientation = scene.interfaceOrientation
        }

        // Pastikan container media selalu mengikuti ukuran preview
        mediaContainer?.frame = preview.bounds
        playerLayer?.frame = mediaContainer?.bounds ?? .zero
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - Tombol Galeri

    private func setupGalleryButton() {
        galleryButton = UIButton(type: .system)
        galleryButton.setTitle("Galeri", for: .normal)
        galleryButton.setTitleColor(.white, for: .normal)
        galleryButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        galleryButton.layer.cornerRadius = 8
        galleryButton.translatesAutoresizingMaskIntoConstraints = false
        galleryButton.addTarget(self, action: #selector(openGallery), for: .touchUpInside)

        view.addSubview(galleryButton)

        NSLayoutConstraint.activate([
            galleryButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            galleryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            galleryButton.widthAnchor.constraint(equalToConstant: 80),
            galleryButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func openGallery() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Tampilan media di dalam preview

    private func clearMedia() {
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }

        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        mediaContainer?.removeFromSuperview()
        mediaContainer = nil
    }

    private func ensureMediaContainer() -> UIView {
        if let container = mediaContainer {
            return container
        }

        let container = UIView(frame: preview.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = .black
        container.clipsToBounds = true
        preview.addSubview(container)
        mediaContainer = container

        return container
    }

    private func showImage(_ image: UIImage) {
        clearMedia()
        let container = ensureMediaContainer()

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(imageView)
    }

    private func playVideo(url: URL) {
        clearMedia()
        let container = ensureMediaContainer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.frame = container.bounds
        layer.videoGravity = .resizeAspectFill
        container.layer.addSublayer(layer)

        self.player = player
        self.playerLayer = layer

        // Loop terus-menerus agar terlihat seperti sedang merekam
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.play()
    }

    // MARK: - IB methods

    @IBAction func recordTapped(_ sender: AnyObject) {

        // Jika sedang menampilkan media galeri, anggap tombol record = "simpan & kembali ke kamera"
        if mediaContainer != nil {
            if let urlAsset = player?.currentItem?.asset as? AVURLAsset {
                let movieURL = urlAsset.url
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized else {
                        DispatchQueue.main.async { self.clearMedia() }
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: movieURL)
                    }, completionHandler: { _, _ in
                        DispatchQueue.main.async { self.clearMedia() }
                    })
                }
            } else {
                // Foto: cukup kembalikan ke kamera
                clearMedia()
            }
            return
        }

        // Alur rekaman kamera asli
        if camera.isRecording() {
            camera.stopRecording()
        } else {
            let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("Movie.mov")
            let configuration = HVTRecordingConfiguration(movieURL: recordingURL)

            do {
                try camera.startRecording(with: configuration)
            } catch {
                print("Cannot record: \(error)")
            }
        }
    }

    // MARK: - Private methods

    func startCamera() {
        camera.startRunning { error in
            if let error = error {
                print("Cannot start the camera: \(error)")
            }
        }
    }

    func removeTempMovie(movieURL: URL) {
        do {
            try FileManager.default.removeItem(at: movieURL)
        } catch _ {
        }
    }

    // MARK: - HVTCameraDelegate methods

    func hvtCameraRecordingDidStart(_ hvtCamera: HVTCamera) {
        recordButton.setTitle("Stop", for: .normal)
    }

    func hvtCamera(_ hvtCamera: HVTCamera, didUpdateRecordingDuration duration: TimeInterval) {
        let seconds = Int(duration)
        var newDuration = "00:00"

        if seconds > 3600 {
            newDuration = NSString(format: "%02lu:%02lu:%02lu", seconds/3600, ((seconds / 60) % 60), seconds % 60) as String
        } else {
            newDuration = NSString(format: "%02lu:%02lu", seconds / 60, seconds % 60) as String
        }

        recordButton.setTitle(newDuration, for: .normal)
    }

    func hvtCamera(_ hvtCamera: HVTCamera, recordingDidFailWithError error: Error) {
        recordButton.setTitle("Record", for: .normal)
    }

    func hvtCamera(_ hvtCamera: HVTCamera, didStopRecordingWithMetadata metadata: [String : Any]) {
        recordButton.setTitle("Record", for: .normal)

        guard let movieURL = metadata[HVTMetadataMovieURLKey] as? URL else {
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: movieURL)
            }, completionHandler: { _, _ in
                self.removeTempMovie(movieURL: movieURL)
            })
        }
    }

    func hvtCamera(_ hvtCamera: HVTCamera, didUpdate params: HVTParams) {
        recordButton.transform = CGAffineTransform(rotationAngle: CGFloat(params.angle))
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let result = results.first else { return }
        let provider = result.itemProvider

        // Video
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let url = url else { return }

                // Salin ke folder temporary karena file representation bersifat sementara
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)

                try? FileManager.default.copyItem(at: url, to: copyURL)

                DispatchQueue.main.async {
                    self?.playVideo(url: copyURL)
                }
            }
            return
        }

        // Foto
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.showImage(image)
                }
            }
        }
    }
}
