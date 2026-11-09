import Foundation

enum DiagramInteraction {
    // Runs only in WebKit's isolated client world, not in the preview document's script world.
    static let script = #"""
    (() => {
        const minimum = 0.01;
        const maximum = 8;
        const states = new WeakMap();
        const clamp = value => Math.min(maximum, Math.max(minimum, value));
        function zoom(state, scale, clientX, clientY) {
            if (!Number.isFinite(scale)) return;
            scale = clamp(scale);
            const rect = state.viewport.getBoundingClientRect();
            const x = clientX - rect.left - state.viewport.clientLeft;
            const y = clientY - rect.top - state.viewport.clientTop;
            const contentX = (state.viewport.scrollLeft + x) / state.scale;
            const contentY = (state.viewport.scrollTop + y) / state.scale;
            state.scale = scale;
            state.viewport.style.setProperty('--diagram-scale', String(scale));
            state.viewport.scrollLeft = contentX * scale - x;
            state.viewport.scrollTop = contentY * scale - y;
            state.slider.value = String(Math.log(scale));
            state.output.value = `${Math.round(scale * 100)}%`;
            state.slider.setAttribute('aria-valuetext', state.output.value);
        }
        function centeredZoom(state, scale) {
            const rect = state.viewport.getBoundingClientRect();
            zoom(state, scale, rect.left + state.viewport.clientLeft + state.viewport.clientWidth / 2,
                 rect.top + state.viewport.clientTop + state.viewport.clientHeight / 2);
        }
        for (const root of document.querySelectorAll('.structure-diagram')) {
            const viewport = root.querySelector('.diagram-viewport');
            const controls = root.querySelector('.diagram-zoom-controls');
            if (!viewport || !controls) continue;
            const state = {viewport, scale: 1};
            const label = document.createElement('label');
            label.textContent = 'Zoom ';
            const slider = document.createElement('input');
            slider.type = 'range';
            slider.min = String(Math.log(minimum));
            slider.max = String(Math.log(maximum));
            slider.step = 'any';
            slider.value = '0';
            slider.setAttribute('aria-label', 'Diagram zoom');
            slider.setAttribute('aria-valuetext', '100%');
            state.slider = slider;
            const output = document.createElement('output');
            output.value = '100%';
            state.output = output;
            label.append(slider);
            const button = (text, description, action) => {
                const element = document.createElement('button');
                element.type = 'button';
                element.textContent = text;
                element.setAttribute('aria-label', description);
                element.addEventListener('click', action);
                return element;
            };
            controls.replaceChildren(
                button('-', 'Zoom diagram out', () => centeredZoom(state, state.scale / 1.2)),
                label,
                button('+', 'Zoom diagram in', () => centeredZoom(state, state.scale * 1.2)),
                output,
                button('100%', 'Reset diagram zoom', () => centeredZoom(state, 1))
            );
            root.querySelectorAll('.diagram-zoom-choice').forEach(input => input.remove());
            slider.addEventListener('input', () => centeredZoom(state, Math.exp(Number(slider.value))));
            // Range controls use logarithmic positions so low zoom levels remain easy to adjust.
            slider.addEventListener('keydown', event => {
                let scale;
                if (event.key === 'ArrowRight' || event.key === 'ArrowUp') scale = state.scale * 1.05;
                if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') scale = state.scale / 1.05;
                if (event.key === 'Home') scale = minimum;
                if (event.key === 'End') scale = maximum;
                if (scale === undefined) return;
                event.preventDefault();
                centeredZoom(state, scale);
            });
            viewport.style.touchAction = 'none';
            viewport.style.overscrollBehavior = 'contain';
            viewport.style.cursor = 'grab';
            let drag;
            viewport.addEventListener('pointerdown', event => {
                if (event.button !== 0 || !event.target.closest('.diagram-svg')) return;
                drag = {id:event.pointerId, x:event.clientX, y:event.clientY,
                        left:viewport.scrollLeft, top:viewport.scrollTop};
                viewport.setPointerCapture(event.pointerId);
                viewport.style.cursor = 'grabbing';
                event.preventDefault();
            });
            viewport.addEventListener('pointermove', event => {
                if (!drag || drag.id !== event.pointerId) return;
                viewport.scrollLeft = drag.left - (event.clientX - drag.x);
                viewport.scrollTop = drag.top - (event.clientY - drag.y);
            });
            const stop = () => { drag = undefined; viewport.style.cursor = 'grab'; };
            viewport.addEventListener('pointerup', stop);
            viewport.addEventListener('pointercancel', stop);
            viewport.addEventListener('lostpointercapture', stop);
            viewport.addEventListener('wheel', event => {
                if (!event.ctrlKey) return;
                event.preventDefault();
                zoom(state, state.scale * Math.exp(-event.deltaY * 0.01), event.clientX, event.clientY);
            }, {passive:false});
            states.set(viewport, state);
        }
        globalThis.fourdDiagramZoom = Object.freeze({
            magnify(x, y, delta) {
                if (![x,y,delta].every(Number.isFinite)) return false;
                const viewport = document.elementFromPoint(x, y)?.closest('.diagram-viewport');
                const state = states.get(viewport);
                if (!state) return false;
                zoom(state, state.scale * Math.exp(delta), x, y);
                return true;
            }
        });
    })();
    """#
}
