// Code syntax highlighting function (must be defined before use)
function highlightCode(code) {
    // Escape HTML to prevent issues
    let highlighted = code
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
    
    // Split into lines to process comments properly
    const lines = highlighted.split('\n');
    const processedLines = lines.map(line => {
        // Check if line has a comment
        const commentMatch = line.match(/(.*?)(\/\/.*)/);
        
        if (commentMatch) {
            // Process code part, then comment
            let codePart = commentMatch[1];
            const comment = commentMatch[2];
            
            // Highlight keywords in code part (before comment)
            const keywords = ['contract', 'function', 'public', 'private', 'internal', 'external', 
                             'returns', 'modifier', 'require', 'if', 'else', 'return', 'mapping', 
                             'struct', 'event', 'emit', 'uint256', 'address', 'bool', 'string',
                             'immutable', 'view', 'pure', 'payable', 'nonReentrant', 'is', 'revert',
                             'calldata', 'memory', 'storage'];
            
            keywords.forEach(keyword => {
                const regex = new RegExp(`\\b${keyword}\\b`, 'g');
                codePart = codePart.replace(regex, `<span class="keyword">${keyword}</span>`);
            });
            
            // Highlight function names in code part (but skip if it's a keyword)
            codePart = codePart.replace(/([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g, (match, funcName) => {
                if (keywords.includes(funcName)) {
                    return match;
                }
                // Check if it looks like a type (starts with capital)
                if (funcName[0] === funcName[0].toUpperCase() && funcName.length > 1) {
                    return `<span class="type">${funcName}</span>(`;
                }
                return `<span class="function">${funcName}</span>(`;
            });
            
            // Highlight strings in code part
            codePart = codePart.replace(/(["'])(?:(?=(\\?))\2.)*?\1/g, (match) => {
                return `<span class="string">${match}</span>`;
            });
            
            return codePart + `<span class="comment">${comment}</span>`;
        } else {
            // No comment, process entire line
            let processedLine = line;
            
            // Highlight strings first (to protect them)
            const stringMatches = [];
            processedLine = processedLine.replace(/(["'])(?:(?=(\\?))\2.)*?\1/g, (match, offset) => {
                stringMatches.push(match);
                return `__STRING_PLACEHOLDER_${stringMatches.length - 1}__`;
            });
            
            // Highlight keywords
            const keywords = ['contract', 'function', 'public', 'private', 'internal', 'external', 
                             'returns', 'modifier', 'require', 'if', 'else', 'return', 'mapping', 
                             'struct', 'event', 'emit', 'uint256', 'address', 'bool', 'string',
                             'immutable', 'view', 'pure', 'payable', 'nonReentrant', 'is', 'revert',
                             'calldata', 'memory', 'storage'];
            
            keywords.forEach(keyword => {
                const regex = new RegExp(`\\b${keyword}\\b`, 'g');
                processedLine = processedLine.replace(regex, `<span class="keyword">${keyword}</span>`);
            });
            
            // Highlight function names and types
            processedLine = processedLine.replace(/([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g, (match, funcName) => {
                if (keywords.includes(funcName)) {
                    return match;
                }
                // Types (capitalized) vs functions
                if (funcName[0] === funcName[0].toUpperCase() && funcName.length > 1) {
                    return `<span class="type">${funcName}</span>(`;
                }
                return `<span class="function">${funcName}</span>(`;
            });
            
            // Highlight numbers
            processedLine = processedLine.replace(/\b(\d+)\b/g, '<span class="number">$1</span>');
            
            // Restore strings
            stringMatches.forEach((str, index) => {
                processedLine = processedLine.replace(
                    `__STRING_PLACEHOLDER_${index}__`,
                    `<span class="string">${str}</span>`
                );
            });
            
            return processedLine;
        }
    });
    
    return processedLines.join('\n');
}

// Wait for DOM to be fully loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
});

function initializeApp() {
// Smooth scroll for navigation links (both nav and sidebar)
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        const href = this.getAttribute('href');
        if (href === '#') return;
        
        e.preventDefault();
        const target = document.querySelector(href);
        if (target) {
            const offset = 80; // Account for fixed navbar
            const targetPosition = target.offsetTop - offset;
            
            window.scrollTo({
                top: targetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// Active sidebar link highlighting
function updateActiveSidebarLink() {
    const sections = document.querySelectorAll('section[id]');
    const sidebarLinks = document.querySelectorAll('.sidebar-link');
    
    let current = '';
    const scrollPosition = window.pageYOffset + 150;
    
    sections.forEach(section => {
        const sectionTop = section.offsetTop;
        const sectionHeight = section.clientHeight;
        const sectionId = section.getAttribute('id');
        
        if (scrollPosition >= sectionTop && scrollPosition < sectionTop + sectionHeight) {
            current = sectionId;
        }
    });
    
    sidebarLinks.forEach(link => {
        link.classList.remove('active');
        const href = link.getAttribute('href');
        if (href === `#${current}`) {
            link.classList.add('active');
        }
    });
}

window.addEventListener('scroll', updateActiveSidebarLink);
updateActiveSidebarLink();
    
    initializeCodeHighlighting();
    initializeAnimations();
    initializeCopyButtons();
}

function initializeCodeHighlighting() {
    // Store original code text before highlighting
    const originalCodeText = new Map();

    // Apply highlighting to all code blocks
    document.querySelectorAll('.code-block code, .code-snippet code').forEach(block => {
        try {
            // Store original text before modifying
            const originalCode = block.textContent || block.innerText;
            if (!originalCode || originalCode.trim() === '') return;
            
            originalCodeText.set(block, originalCode);
            
            // Apply highlighting only if we have content
            const highlighted = highlightCode(originalCode);
            if (highlighted && highlighted !== originalCode) {
                block.innerHTML = highlighted;
            }
        } catch (error) {
            console.error('Error highlighting code:', error);
            // If highlighting fails, just keep the original code
        }
    });
    
    // Store in global scope for copy buttons
    window.originalCodeText = originalCodeText;
}

function initializeAnimations() {
    // Navbar scroll effect
    const nav = document.querySelector('.nav');
    if (nav) {
        window.addEventListener('scroll', () => {
            const currentScroll = window.pageYOffset;
            
            if (currentScroll > 100) {
                nav.style.background = 'rgba(10, 10, 15, 0.95)';
            } else {
                nav.style.background = 'rgba(10, 10, 15, 0.8)';
            }
        });
    }

    // Intersection Observer for fade-in animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, observerOptions);

    // Observe elements for animation
    document.querySelectorAll('.solution-card, .arch-card, .benefit-card, .timeline-item').forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(20px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });
}

function initializeCopyButtons() {
    // Add copy button to code blocks
    document.querySelectorAll('.code-block').forEach(block => {
    const button = document.createElement('button');
    button.className = 'copy-button';
    button.textContent = 'Copy';
    button.style.cssText = `
        position: absolute;
        top: 1rem;
        right: 1rem;
        padding: 0.5rem 1rem;
        background: var(--bg-tertiary);
        border: 1px solid var(--border-color);
        border-radius: 6px;
        color: var(--text-secondary);
        cursor: pointer;
        font-size: 0.75rem;
        transition: all 0.2s;
        z-index: 10;
    `;
    
    button.addEventListener('mouseenter', () => {
        button.style.background = 'var(--accent-primary)';
        button.style.color = 'white';
        button.style.borderColor = 'var(--accent-primary)';
    });
    
    button.addEventListener('mouseleave', () => {
        button.style.background = 'var(--bg-tertiary)';
        button.style.color = 'var(--text-secondary)';
        button.style.borderColor = 'var(--border-color)';
    });
    
    button.addEventListener('click', () => {
        const codeElement = block.querySelector('code');
        const originalText = window.originalCodeText?.get(codeElement) || codeElement.textContent;
        navigator.clipboard.writeText(originalText).then(() => {
            button.textContent = 'Copied!';
            setTimeout(() => {
                button.textContent = 'Copy';
            }, 2000);
        }).catch(err => {
            console.error('Failed to copy:', err);
            button.textContent = 'Error';
            setTimeout(() => {
                button.textContent = 'Copy';
            }, 2000);
        });
    });
    
    const codeHeader = block.querySelector('.code-header');
    if (codeHeader) {
        codeHeader.style.position = 'relative';
        codeHeader.appendChild(button);
    } else {
        block.style.position = 'relative';
        block.appendChild(button);
    }
    });
}

// Fallback: If DOMContentLoaded already fired, run immediately
if (document.readyState === 'loading') {
    // DOMContentLoaded has not fired yet
    document.addEventListener('DOMContentLoaded', initializeApp);
} else {
    // DOMContentLoaded has already fired
    initializeApp();
}
