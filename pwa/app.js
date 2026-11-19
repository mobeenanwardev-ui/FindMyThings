(() => {
  'use strict';
  const DB_NAME = 'findmythings-pwa';
  const DB_VERSION = 1;
  const STORE = 'belongings';
  let db;
  let editingId = null;
  let selectedPhoto = null;
  let toastTimer;

  const $ = (id) => document.getElementById(id);
  const els = {
    count: $('item-count'), grid: $('items-grid'), empty: $('empty-state'),
    emptyTitle: $('empty-title'), emptyCopy: $('empty-copy'),
    search: $('search-input'), dialog: $('item-dialog'), form: $('item-form'),
    name: $('item-name'), category: $('item-category'), input: $('photo-input'),
    preview: $('photo-preview'), placeholder: $('photo-placeholder'),
    removePhoto: $('remove-photo'), error: $('form-error'), save: $('save-button'),
    title: $('dialog-title'), status: $('photo-status'), toast: $('toast')
  };

  function openDatabase() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const database = request.result;
        if (!database.objectStoreNames.contains(STORE)) {
          database.createObjectStore(STORE, { keyPath: 'id' });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  function transaction(mode, action) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const request = action(tx.objectStore(STORE));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      tx.onabort = () => reject(tx.error || new Error('Storage transaction failed'));
    });
  }
  const getAll = () => transaction('readonly', store => store.getAll());
  const put = item => transaction('readwrite', store => store.put(item));
  const remove = id => transaction('readwrite', store => store.delete(id));

  function notify(message) {
    els.toast.textContent = message;
    els.toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => els.toast.classList.remove('show'), 2300);
  }
  function formatCount(n) { return n + (n === 1 ? ' thing saved' : ' things saved'); }
  function makeCard(item) {
    const card = document.createElement('article');
    card.className = 'item-card';
    if (item.photo) {
      const image = document.createElement('img');
      image.className = 'item-photo';
      image.alt = item.name;
      image.src = URL.createObjectURL(item.photo);
      card.append(image);
    } else {
      const placeholder = document.createElement('div');
      placeholder.className = 'item-placeholder';
      placeholder.textContent = '▧';
      card.append(placeholder);
    }
    const info = document.createElement('div');
    info.className = 'item-info';
    const name = document.createElement('p');
    name.className = 'item-name';
    name.textContent = item.name;
    const category = document.createElement('p');
    category.className = 'item-category';
    category.textContent = item.category || 'My belongings';
    const actions = document.createElement('div');
    actions.className = 'item-actions';
    const edit = document.createElement('button');
    edit.type = 'button'; edit.className = 'small-button'; edit.textContent = 'Edit';
    edit.addEventListener('click', () => openEditor(item));
    const find = document.createElement('button');
    find.type = 'button'; find.className = 'small-button find-button';
    find.textContent = 'Find it'; find.disabled = !item.photo;
    find.title = item.photo ? 'Open camera to look for this item' : 'Add a reference photo first';
    find.addEventListener('click', () => openScanner(item));
    const del = document.createElement('button');
    del.type = 'button'; del.className = 'small-button delete'; del.textContent = 'Delete';
    del.addEventListener('click', async () => {
      if (!confirm('Delete ' + item.name + ' from this device?')) return;
      await remove(item.id); await render(); notify('Belonging deleted');
    });
    actions.append(edit, find, del); info.append(name, category, actions); card.append(info);
    return card;
  }
  async function render() {
    const items = (await getAll()).sort((a,b) => b.created - a.created);
    const query = els.search.value.trim().toLowerCase();
    const filtered = items.filter(item => (item.name + ' ' + (item.category || '')).toLowerCase().includes(query));
    els.count.textContent = formatCount(items.length);
    els.grid.replaceChildren(...filtered.map(makeCard));
    const noItems = items.length === 0;
    els.empty.hidden = filtered.length !== 0;
    els.emptyTitle.textContent = noItems ? 'Nothing here yet' : 'No matches found';
    els.emptyCopy.textContent = noItems ? 'Add your first belonging with a reference photo.' : 'Try another name.';
    $('empty-add-button').hidden = !noItems;
  }
  function showPhoto(blob) {
    selectedPhoto = blob || null;
    if (selectedPhoto) {
      els.preview.src = URL.createObjectURL(selectedPhoto);
      els.preview.hidden = false;
      els.placeholder.hidden = true;
      els.removePhoto.hidden = false;
      els.status.textContent = 'Photo selected';
    } else {
      els.preview.removeAttribute('src');
      els.preview.hidden = true;
      els.placeholder.hidden = false;
      els.removePhoto.hidden = true;
      els.status.textContent = 'One photo';
    }
  }
  function openEditor(item) {
    editingId = item ? item.id : null;
    els.title.textContent = item ? 'Edit your thing' : 'Add a thing';
    els.name.value = item ? item.name : '';
    els.category.value = item ? item.category : 'My belongings';
    els.error.textContent = '';
    els.input.value = '';
    showPhoto(item ? item.photo : null);
    els.save.textContent = item ? 'Save changes' : 'Save belonging';
    els.dialog.showModal();
    setTimeout(() => els.name.focus(), 80);
  }
  function closeEditor() { els.dialog.close(); }
  function compressImage(file) {
    return new Promise((resolve, reject) => {
      if (!file || !file.type.startsWith('image/')) return reject(new Error('Choose an image file.'));
      const image = new Image();
      const sourceUrl = URL.createObjectURL(file);
      image.onload = () => {
        const maxSide = 1800;
        const scale = Math.min(1, maxSide / Math.max(image.width, image.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(image.width * scale));
        canvas.height = Math.max(1, Math.round(image.height * scale));
        const ctx = canvas.getContext('2d');
        ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(sourceUrl);
        canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error('Could not process this photo.')), 'image/jpeg', .86);
      };
      image.onerror = () => { URL.revokeObjectURL(sourceUrl); reject(new Error('Could not read this photo.')); };
      image.src = sourceUrl;
    });
  }


  // On-device visual similarity scanner. MobileNet produces image features locally;
  // it does not provide a trained "wallet" detector or guarantee an exact match.
  const scan = {
    dialog: $('scan-dialog'), video: $('camera-video'), reference: $('scan-reference'),
    itemName: $('scan-item-name'), state: $('camera-state'), label: $('match-label'),
    score: $('match-score'), bar: $('match-bar'), guidance: $('match-guidance')
  };
  let cameraStream = null;
  let visionModel = null;
  let scanTimer = null;
  let scanBusy = false;
  let scanActive = false;
  let targetEmbedding = null;
  let scanTargetUrl = null;

  function cosineSimilarity(a, b) {
    let dot = 0, aa = 0, bb = 0;
    for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i]; }
    return dot / (Math.sqrt(aa) * Math.sqrt(bb) || 1);
  }
  async function getVisionModel() {
    if (visionModel) return visionModel;
    if (!window.tf || !window.mobilenet) throw new Error('The visual model could not be loaded. Check your internet connection and reload the app.');
    scan.state.textContent = 'Loading visual model…';
    scan.guidance.textContent = 'Downloading MobileNet for on-device image comparison. This can take a little while the first time.';
    await tf.ready();
    try { await tf.setBackend('webgl'); await tf.ready(); } catch (_) { /* Use the available TensorFlow.js backend. */ }
    visionModel = await mobilenet.load({version: 2, alpha: 1.0});
    return visionModel;
  }
  function extractEmbedding(source) {
    return tf.tidy(() => Array.from(visionModel.infer(source, true).flatten().dataSync()));
  }
  function stopScanner() {
    scanActive = false;
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = null;
    if (cameraStream) cameraStream.getTracks().forEach(track => track.stop());
    cameraStream = null;
    scan.video.pause();
    scan.video.srcObject = null;
    if (scanTargetUrl) URL.revokeObjectURL(scanTargetUrl);
    scanTargetUrl = null;
    scanBusy = false;
    if (scan.dialog.open) scan.dialog.close();
  }
  async function openScanner(item) {
    if (!item.photo) { notify('Add a reference photo before scanning'); return; }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      notify('Camera access is not available in this browser');
      return;
    }
    scan.itemName.textContent = item.name;
    scan.reference.src = scanTargetUrl = URL.createObjectURL(item.photo);
    scan.label.textContent = 'Preparing visual comparison';
    scan.score.textContent = '—';
    scan.bar.style.width = '0%';
    scan.guidance.textContent = 'Allow camera access. Keep the item reasonably close and fill much of the camera view.';
    scan.dialog.showModal();
    scanActive = true;
    try {
      const model = await getVisionModel();
      if (!scanActive) return;
      const referenceImage = new Image();
      referenceImage.src = scanTargetUrl;
      await new Promise((resolve, reject) => {
        referenceImage.onload = resolve;
        referenceImage.onerror = () => reject(new Error('Could not read the saved reference photo.'));
      });
      targetEmbedding = extractEmbedding(referenceImage);
      cameraStream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: {facingMode: {ideal: 'environment'}, width: {ideal: 640}, height: {ideal: 480}}
      });
      if (!scanActive) { cameraStream.getTracks().forEach(track => track.stop()); return; }
      scan.video.srcObject = cameraStream;
      await scan.video.play();
      scan.state.textContent = 'Camera active';
      scan.label.textContent = 'Looking for visual similarity';
      scan.guidance.textContent = 'Move slowly, change the angle, and bring the item into the centre of the frame.';
      scanFrame();
    } catch (error) {
      scan.state.textContent = 'Scanner could not start';
      scan.label.textContent = 'Camera or model unavailable';
      scan.guidance.textContent = error.name === 'NotAllowedError'
        ? 'Camera permission was denied. Allow camera access for this website in iPhone Settings and try again.'
        : (error.message || 'Check camera permission and internet access, then try again.');
      if (cameraStream) cameraStream.getTracks().forEach(track => track.stop());
      cameraStream = null;
    }
  }
  function scanFrame() {
    if (!scanActive || !cameraStream || scanBusy) return;
    if (scan.video.readyState < 2) {
      scanTimer = setTimeout(scanFrame, 500);
      return;
    }
    scanBusy = true;
    try {
      const currentEmbedding = extractEmbedding(scan.video);
      const similarity = Math.max(0, Math.min(1, cosineSimilarity(targetEmbedding, currentEmbedding)));
      const percent = Math.round(similarity * 100);
      scan.score.textContent = percent + '%';
      scan.bar.style.width = percent + '%';
      if (similarity >= 0.84) {
        scan.label.textContent = 'Strong visual similarity';
        scan.state.textContent = 'Possible match in view';
        scan.guidance.textContent = 'A possible match is visible. Check the object carefully; this score is not proof that it is your item.';
      } else if (similarity >= 0.70) {
        scan.label.textContent = 'Some visual similarity';
        scan.state.textContent = 'Keep scanning…';
        scan.guidance.textContent = 'Not confident yet. Move closer, centre the object, and try another angle.';
      } else {
        scan.label.textContent = 'No clear visual match';
        scan.state.textContent = 'Searching surroundings…';
        scan.guidance.textContent = 'Try a different angle and make the item fill more of the camera view.';
      }
    } catch (error) {
      scan.label.textContent = 'Could not analyse this frame';
      scan.guidance.textContent = error.message || 'Try again.';
    } finally {
      scanBusy = false;
      if (scanActive) scanTimer = setTimeout(scanFrame, 1000);
    }
  }

  $('scan-close').addEventListener('click', stopScanner);
  $('scan-stop').addEventListener('click', stopScanner);
  scan.dialog.addEventListener('cancel', event => { event.preventDefault(); stopScanner(); });

  $('add-button').addEventListener('click', () => openEditor(null));
  $('empty-add-button').addEventListener('click', () => openEditor(null));
  $('close-dialog').addEventListener('click', closeEditor);
  $('cancel-button').addEventListener('click', closeEditor);
  els.search.addEventListener('input', render);
  els.input.addEventListener('change', async () => {
    const file = els.input.files && els.input.files[0];
    if (!file) return;
    try { showPhoto(await compressImage(file)); els.error.textContent = ''; }
    catch (error) { els.error.textContent = error.message; }
  });
  els.removePhoto.addEventListener('click', () => { showPhoto(null); els.input.value = ''; });
  els.form.addEventListener('submit', async event => {
    event.preventDefault();
    const name = els.name.value.trim();
    if (!name) { els.error.textContent = 'Give your thing a name first.'; return; }
    els.save.disabled = true; els.save.textContent = 'Saving…'; els.error.textContent = '';
    try {
      const previous = editingId ? await transaction('readonly', store => store.get(editingId)) : null;
      await put({
        id: editingId || (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())),
        name,
        category: els.category.value.trim() || 'My belongings',
        photo: selectedPhoto,
        created: previous ? previous.created : Date.now(),
        updated: Date.now()
      });
      closeEditor(); await render(); notify('Saved ' + name);
    } catch (error) {
      els.error.textContent = 'Could not save this item. Your browser storage may be full.';
    } finally { els.save.disabled = false; els.save.textContent = editingId ? 'Save changes' : 'Save belonging'; }
  });

  window.addEventListener('online', () => { $('connection-label').textContent = 'On this device'; });
  window.addEventListener('offline', () => { $('connection-label').textContent = 'Offline mode'; });
  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(err => console.warn('Offline setup unavailable', err)));
  }
  (async () => {
    try { db = await openDatabase(); await render(); }
    catch (error) {
      els.empty.hidden = false;
      els.emptyTitle.textContent = 'Local storage unavailable';
      els.emptyCopy.textContent = 'Please open FindMyThings in Safari or another modern browser.';
      console.error(error);
    }
  })();
})();