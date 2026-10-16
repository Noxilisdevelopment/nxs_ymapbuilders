let currentCategories = [];
let allProps = [];
let placedEntities = [];
let selectedCategory = 'all';
let generatedXml = '';

// Sélecteurs
const app = document.getElementById('app');
const closeBtn = document.getElementById('closeBtn');
const propSearch = document.getElementById('propSearch');
const clearSearch = document.getElementById('clearSearch');
const categoriesBar = document.getElementById('categoriesBar');
const propsGrid = document.getElementById('propsGrid');
const customPropInput = document.getElementById('customPropInput');
const spawnCustomBtn = document.getElementById('spawnCustomBtn');
const placedCount = document.getElementById('placedCount');
const placedCountTab = document.getElementById('placedCountTab');
const placedList = document.getElementById('placedList');
const clearAllBtn = document.getElementById('clearAllBtn');
const mapNameInput = document.getElementById('mapNameInput');
const generateYmapBtn = document.getElementById('generateYmapBtn');
const copyXmlBtn = document.getElementById('copyXmlBtn');
const xmlPreview = document.getElementById('xmlPreview');
const tabButtons = document.querySelectorAll('.tab-btn');
const tabContents = document.querySelectorAll('.tab-content');
const toastContainer = document.getElementById('toastContainer');
const confirmModal = document.getElementById('confirmModal');
const confirmTitle = document.getElementById('confirmTitle');
const confirmDesc = document.getElementById('confirmDesc');
const confirmCancelBtn = document.getElementById('confirmCancelBtn');
const confirmOkBtn = document.getElementById('confirmOkBtn');
const undoBtn = document.getElementById('undoBtn');
const redoBtn = document.getElementById('redoBtn');
const refreshProjectsBtn = document.getElementById('refreshProjectsBtn');
const projectsList = document.getElementById('projectsList');
let onConfirmCallback = null;

// Helper API FiveM
function post(event, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then(resp => resp.json()).catch(() => ({}));
}

// Initialisation des données reçues du client Lua
window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.action === 'openUI') {
        currentCategories = data.categories || [];
        placedEntities = data.placedEntities || [];
        
        // Aplatir tous les props pour la recherche
        allProps = [];
        currentCategories.forEach(cat => {
            cat.props.forEach(p => {
                allProps.push({
                    label: p.label,
                    model: p.model,
                    categoryId: cat.id
                });
            });
        });

        renderCategories();
        renderPropsGrid();
        renderPlacedList();
        updateCounts();

        app.classList.remove('hidden');
    } else if (data.action === 'updatePlaced') {
        placedEntities = data.placedEntities || [];
        renderPlacedList();
        updateCounts();
    } else if (data.action === 'forceClose') {
        app.classList.add('hidden');
    }
});

// Fermer l'UI
function closeUI() {
    app.classList.add('hidden');
    post('closeUI');
}

closeBtn.addEventListener('click', closeUI);

const worldBackdrop = document.getElementById('worldBackdrop');
if (worldBackdrop) {
    worldBackdrop.addEventListener('click', (e) => {
        if (e.button !== 0) return;
        const normX = e.clientX / window.innerWidth;
        const normY = e.clientY / window.innerHeight;
        post('clickWorldProp', { x: normX, y: normY });
    });
}

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeUI();
    }
});

// Gestion des Onglets
tabButtons.forEach(btn => {
    btn.addEventListener('click', () => {
        tabButtons.forEach(b => b.classList.remove('active'));
        tabContents.forEach(c => c.classList.remove('active'));

        btn.classList.add('active');
        const tabTarget = document.getElementById(`tab-${btn.dataset.tab}`);
        if (tabTarget) tabTarget.classList.add('active');

        if (btn.dataset.tab === 'projects') {
            renderProjectsList();
        }
    });
});

// Rendu des catégories
function renderCategories() {
    categoriesBar.innerHTML = '';

    // Chip "Tous"
    const allChip = document.createElement('div');
    allChip.className = `category-chip ${selectedCategory === 'all' ? 'active' : ''}`;
    allChip.innerHTML = `<i class="fa-solid fa-border-all"></i> Tous`;
    allChip.addEventListener('click', () => {
        selectedCategory = 'all';
        renderCategories();
        renderPropsGrid();
    });
    categoriesBar.appendChild(allChip);

    currentCategories.forEach(cat => {
        const chip = document.createElement('div');
        chip.className = `category-chip ${selectedCategory === cat.id ? 'active' : ''}`;
        chip.innerHTML = `<i class="${cat.icon || 'fa-solid fa-cube'}"></i> ${cat.name}`;
        chip.addEventListener('click', () => {
            selectedCategory = cat.id;
            renderCategories();
            renderPropsGrid();
        });
        categoriesBar.appendChild(chip);
    });
}

// Rendu de la grille des props
function renderPropsGrid() {
    propsGrid.innerHTML = '';
    const query = propSearch.value.trim().toLowerCase();

    const filtered = allProps.filter(p => {
        const matchesCategory = selectedCategory === 'all' || p.categoryId === selectedCategory;
        const matchesQuery = query === '' || p.label.toLowerCase().includes(query) || p.model.toLowerCase().includes(query);
        return matchesCategory && matchesQuery;
    });

    if (filtered.length === 0) {
        propsGrid.innerHTML = `
            <div style="grid-column: 1 / -1; text-align: center; padding: 40px; color: var(--text-secondary);">
                <i class="fa-regular fa-folder-open" style="font-size: 32px; margin-bottom: 10px; display: block; color: var(--text-muted);"></i>
                <span style="color: var(--text-primary); font-weight: 500;">Aucun prop trouvé pour cette recherche.</span><br>
                <span style="font-size: 11.5px; color: var(--text-muted);">Vous pouvez saisir directement son nom technique dans le champ "Prop personnalisé" ci-dessus !</span>
            </div>
        `;
        return;
    }

    filtered.forEach(prop => {
        const card = document.createElement('div');
        card.className = 'prop-card';

        // Source de l'image (locale ou URL custom)
        const imgSrc = prop.image ? prop.image : `img/props/${prop.model}.png`;
        const cat = currentCategories.find(c => c.id === prop.categoryId);
        const iconClass = cat ? (cat.icon || 'fa-solid fa-cube') : 'fa-solid fa-cube';

        card.innerHTML = `
            <div class="prop-thumb-wrapper">
                <img src="${imgSrc}" class="prop-thumb-img" alt="${escapeHtml(prop.label)}" 
                     onload="this.style.display='block'; this.nextElementSibling.style.display='none';" 
                     onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                <div class="prop-thumb-placeholder">
                    <i class="${iconClass}"></i>
                </div>
            </div>
            <div class="prop-card-body">
                <div class="prop-card-content">
                    <div class="prop-name">${escapeHtml(prop.label)}</div>
                    <div class="prop-model">${escapeHtml(prop.model)}</div>
                </div>
                <div class="prop-action-icon"><i class="fa-solid fa-plus"></i></div>
            </div>
        `;

        card.addEventListener('click', () => {
            post('startPlacement', { model: prop.model });
            app.classList.add('hidden');
        });

        propsGrid.appendChild(card);
    });
}

// Recherche
propSearch.addEventListener('input', () => {
    clearSearch.classList.toggle('hidden', propSearch.value.trim() === '');
    renderPropsGrid();
});

clearSearch.addEventListener('click', () => {
    propSearch.value = '';
    clearSearch.classList.add('hidden');
    renderPropsGrid();
});

// Poser un prop personnalisé (Custom input)
spawnCustomBtn.addEventListener('click', () => {
    const model = customPropInput.value.trim();
    if (!model) return;
    post('startPlacement', { model: model });
    app.classList.add('hidden');
});

customPropInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        spawnCustomBtn.click();
    }
});

// Objets placés (Onglet 2)
function renderPlacedList() {
    placedList.innerHTML = '';

    if (placedEntities.length === 0) {
        placedList.innerHTML = `
            <div style="text-align: center; padding: 50px; color: var(--text-secondary);">
                <i class="fa-solid fa-box-open" style="font-size: 36px; margin-bottom: 12px; display: block; color: var(--text-muted);"></i>
                <span style="color: var(--text-primary); font-weight: 500;">Aucun objet n'a encore été posé.</span><br>
                <span style="font-size: 11.5px; color: var(--text-muted);">Sélectionnez un prop dans le catalogue pour commencer à mapper !</span>
            </div>
        `;
        return;
    }

    placedEntities.forEach(ent => {
        const item = document.createElement('div');
        item.className = 'placed-item';
        
        const cX = ent.coords ? ent.coords.x.toFixed(2) : '0';
        const cY = ent.coords ? ent.coords.y.toFixed(2) : '0';
        const cZ = ent.coords ? ent.coords.z.toFixed(2) : '0';

        item.innerHTML = `
            <div class="placed-info">
                <div class="placed-id">#${ent.id}</div>
                <div class="placed-details">
                    <span class="placed-model">${escapeHtml(ent.model)}</span>
                    <span class="placed-coords">X: ${cX} | Y: ${cY} | Z: ${cZ}</span>
                </div>
            </div>
            <div class="placed-actions">
                <button class="action-btn" title="Téléporter à l'objet" data-action="tp">
                    <i class="fa-solid fa-location-arrow"></i> TP
                </button>
                <button class="action-btn gizmo-btn" title="Ajuster avec Gizmo 3D" data-action="gizmo">
                    <i class="fa-solid fa-up-down-left-right"></i> Gizmo
                </button>
                <button class="action-btn" title="Dupliquer" data-action="duplicate">
                    <i class="fa-solid fa-clone"></i> Cloner
                </button>
                <button class="action-btn delete-btn" title="Supprimer" data-action="delete">
                    <i class="fa-solid fa-trash"></i>
                </button>
            </div>
        `;

        // Clic sur l'élément pour le sélectionner immédiatement au Gizmo
        item.title = 'Cliquer pour sélectionner et ajuster avec le Gizmo 3D';
        item.addEventListener('click', (e) => {
            if (e.target.closest('button')) return;
            post('editPropGizmo', { id: ent.id });
            app.classList.add('hidden');
        });

        // Highlight au survol
        item.addEventListener('mouseenter', () => {
            post('highlightProp', { id: ent.id });
        });

        // Actions
        item.querySelector('[data-action="tp"]').addEventListener('click', (e) => {
            e.stopPropagation();
            post('teleportToProp', { id: ent.id });
        });

        item.querySelector('[data-action="gizmo"]').addEventListener('click', (e) => {
            e.stopPropagation();
            post('editPropGizmo', { id: ent.id });
            app.classList.add('hidden');
        });

        item.querySelector('[data-action="duplicate"]').addEventListener('click', (e) => {
            e.stopPropagation();
            post('duplicateProp', { id: ent.id });
            app.classList.add('hidden');
        });

        item.querySelector('[data-action="delete"]').addEventListener('click', (e) => {
            e.stopPropagation();
            post('deleteProp', { id: ent.id }).then(res => {
                if (res && res.placedEntities) {
                    placedEntities = res.placedEntities;
                    renderPlacedList();
                    updateCounts();
                }
            });
        });

        placedList.appendChild(item);
    });
}

// Système de Notifications Toast NUI
function showToast(title, message, type = 'info', duration = 3500) {
    if (!toastContainer) return;

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;

    let iconClass = 'fa-solid fa-circle-info';
    if (type === 'error') iconClass = 'fa-solid fa-circle-exclamation';
    else if (type === 'success') iconClass = 'fa-solid fa-circle-check';
    else if (type === 'warning') iconClass = 'fa-solid fa-triangle-exclamation';

    toast.innerHTML = `
        <div class="toast-icon"><i class="${iconClass}"></i></div>
        <div class="toast-body">
            <span class="toast-title">${escapeHtml(title)}</span>
            <span class="toast-message">${escapeHtml(message)}</span>
        </div>
    `;

    toastContainer.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('toast-hiding');
        setTimeout(() => {
            if (toast.parentNode) toast.parentNode.removeChild(toast);
        }, 200);
    }, duration);
}

// Système de Confirmation NUI Interne
function showConfirm(title, message, callback) {
    if (!confirmModal) {
        if (callback) callback();
        return;
    }
    confirmTitle.textContent = title || 'Confirmation';
    confirmDesc.textContent = message || 'Voulez-vous vraiment confirmer ?';
    onConfirmCallback = callback;
    confirmModal.classList.remove('hidden');
}

confirmCancelBtn.addEventListener('click', () => {
    confirmModal.classList.add('hidden');
    onConfirmCallback = null;
});

confirmOkBtn.addEventListener('click', () => {
    confirmModal.classList.add('hidden');
    if (onConfirmCallback) {
        onConfirmCallback();
        onConfirmCallback = null;
    }
});

// Tout supprimer avec confirmation NUI
clearAllBtn.addEventListener('click', () => {
    showConfirm(
        'Vider la scène',
        'Voulez-vous vraiment supprimer tous les props placés dans cette session ?',
        () => {
            post('clearAllProps').then(res => {
                if (res) {
                    placedEntities = [];
                    renderPlacedList();
                    updateCounts();
                    showToast('Nettoyage', 'Tous les props ont été supprimés.', 'warning');
                }
            });
        }
    );
});

// Mise à jour des compteurs
function updateCounts() {
    const count = placedEntities.length;
    placedCount.textContent = count;
    placedCountTab.textContent = count;
}

// Export YMAP (Onglet 3) avec Toast NUI
generateYmapBtn.addEventListener('click', () => {
    const mapName = mapNameInput.value.trim() || 'mapping';

    if (placedEntities.length === 0) {
        showToast('Export YMAP', 'Veuillez placer au moins un prop avant de générer le YMAP !', 'warning');
        return;
    }

    generateYmapBtn.disabled = true;
    generateYmapBtn.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> Génération...`;

    post('exportYmap', { name: mapName }).then(res => {
        generateYmapBtn.disabled = false;
        generateYmapBtn.innerHTML = `<i class="fa-solid fa-file-code"></i> Générer le YMAP (.xml)`;

        if (res && res.success) {
            generatedXml = res.xmlContent;
            xmlPreview.textContent = generatedXml;
            copyXmlBtn.classList.remove('hidden');

            document.getElementById('xmlStatusBadge').textContent = `Exporté : ${res.fileName} (${res.totalEntities} props)`;
            document.getElementById('xmlStatusBadge').style.color = 'var(--success)';

            showToast('Export Réussi', `Le fichier ${res.fileName} a été créé dans exports/ !`, 'success');
        } else {
            showToast('Erreur Export', res.message || 'Une erreur est survenue lors de l\'export.', 'error');
        }
    });
});

// Copier dans le presse-papier avec Toast
copyXmlBtn.addEventListener('click', () => {
    if (!generatedXml) return;
    navigator.clipboard.writeText(generatedXml).then(() => {
        const originalText = copyXmlBtn.innerHTML;
        copyXmlBtn.innerHTML = `<i class="fa-solid fa-check"></i> Copié !`;
        copyXmlBtn.style.background = 'rgba(16, 185, 129, 0.2)';
        copyXmlBtn.style.borderColor = 'var(--success)';
        showToast('Presse-papier', 'Code XML copié dans votre presse-papier !', 'info', 2000);
        setTimeout(() => {
            copyXmlBtn.innerHTML = originalText;
            copyXmlBtn.style.background = '';
            copyXmlBtn.style.borderColor = '';
        }, 2000);
    });
});

// Annuler / Rétablir (Undo / Redo)
if (undoBtn) {
    undoBtn.addEventListener('click', () => {
        post('undo').then(res => {
            if (res && res.placedEntities) {
                placedEntities = res.placedEntities;
                renderPlacedList();
                updateCounts();
            }
        });
    });
}

if (redoBtn) {
    redoBtn.addEventListener('click', () => {
        post('redo').then(res => {
            if (res && res.placedEntities) {
                placedEntities = res.placedEntities;
                renderPlacedList();
                updateCounts();
            }
        });
    });
}

// Rendu du Gestionnaire de Projets (Onglet 4)
function renderProjectsList() {
    if (!projectsList) return;
    projectsList.innerHTML = `
        <div style="text-align: center; padding: 40px; color: var(--text-muted);">
            <i class="fa-solid fa-spinner fa-spin" style="font-size: 24px; margin-bottom: 8px; display: block;"></i>
            Chargement des projets sauvegardés...
        </div>
    `;

    post('getProjects').then(res => {
        projectsList.innerHTML = '';
        const projects = res && res.projects ? res.projects : [];
        if (projects.length === 0) {
            projectsList.innerHTML = `
                <div style="text-align: center; padding: 50px; color: var(--text-secondary);">
                    <i class="fa-regular fa-folder" style="font-size: 36px; margin-bottom: 12px; display: block; color: var(--text-muted);"></i>
                    <span style="color: var(--text-primary); font-weight: 500;">Aucun projet enregistré.</span><br>
                    <span style="font-size: 11.5px; color: var(--text-muted);">Sauvegardez vos créations via l'onglet "Exporter" pour les retrouver ici à tout moment !</span>
                </div>
            `;
            return;
        }

        projects.forEach(p => {
            const card = document.createElement('div');
            card.className = 'project-card';
            card.innerHTML = `
                <div class="project-card-header">
                    <span class="project-title"><i class="fa-solid fa-cube"></i> ${escapeHtml(p.name)}</span>
                    <span class="project-date">${escapeHtml(p.createdAt || '')}</span>
                </div>
                <div class="project-meta">
                    <span><i class="fa-solid fa-layer-group"></i> ${p.entitiesCount || 0} props</span>
                </div>
                <div class="project-actions">
                    <button class="btn btn-primary load-project-btn" data-name="${escapeHtml(p.name)}">
                        <i class="fa-solid fa-folder-open"></i> Charger le projet
                    </button>
                    <button class="btn btn-secondary delete-project-btn" data-name="${escapeHtml(p.name)}" style="flex: 0 0 40px; justify-content: center;" title="Supprimer la sauvegarde">
                        <i class="fa-solid fa-trash" style="color: var(--danger);"></i>
                    </button>
                </div>
            `;

            card.querySelector('.load-project-btn').addEventListener('click', () => {
                showConfirm('Charger ce projet ?', `Les props actuels seront remplacés par la sauvegarde "${p.name}".`, () => {
                    post('loadProject', { name: p.name }).then(loadRes => {
                        if (loadRes && loadRes.success) {
                            placedEntities = loadRes.placedEntities || [];
                            renderPlacedList();
                            updateCounts();
                            showToast('Projet Chargé', `Le projet "${p.name}" a été chargé avec succès !`, 'success');
                            // Basculer vers l'onglet des props posés
                            const placedTabBtn = document.querySelector('.tab-btn[data-tab="placed"]');
                            if (placedTabBtn) placedTabBtn.click();
                        }
                    });
                });
            });

            card.querySelector('.delete-project-btn').addEventListener('click', () => {
                showConfirm('Supprimer ce projet ?', `Le projet "${p.name}" sera retiré de la liste des sauvegardes.`, () => {
                    post('deleteProject', { name: p.name }).then(() => {
                        renderProjectsList();
                        showToast('Suppression', `Projet "${p.name}" supprimé.`, 'info');
                    });
                });
            });

            projectsList.appendChild(card);
        });
    });
}

if (refreshProjectsBtn) {
    refreshProjectsBtn.addEventListener('click', renderProjectsList);
}

// Helper XSS
function escapeHtml(text) {
    if (!text) return '';
    return text.toString()
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}
