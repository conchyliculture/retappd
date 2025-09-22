class BeerDashboard {
  constructor() {
    window.dashboard = this;
    this.setupModalEventListeners();
    this.init();
  }

  setupModalEventListeners() {
    // Close modal when clicking outside of it
    document.addEventListener('click', (e) => {
      if (e.target.classList.contains('modal-backdrop')) {
        if (e.target.id === 'venue-modal-backdrop') {
          this.closeVenueModal();
        } else if (e.target.id === 'beer-venues-modal-backdrop') {
          this.closeBeerVenuesModal();
        }
      }
    });

    // Close modal with Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        const venueModal = document.getElementById('venue-modal');
        const beerVenuesModal = document.getElementById('beer-venues-modal');

        if (venueModal.classList.contains('show')) {
          this.closeVenueModal();
        } else if (beerVenuesModal.classList.contains('show')) {
          this.closeBeerVenuesModal();
        }
      }
    });
  }

  async init() {
    await this.loadStats();
    await this.loadTopBeers();
    await this.loadCharts();
    await this.initMapVenues();
    await this.initMapBreweries();
  }

  async fetchData(endpoint) {
    const response = await fetch(`/api/${endpoint}`);
    return response.json();
  }

  async loadStats() {
    try {
      const stats = await this.fetchData('stats');
      document.getElementById('total-checkins').textContent = stats.total_checkins.toLocaleString();
      document.getElementById('unique-beers').textContent = stats.unique_beers.toLocaleString();
      document.getElementById('total-breweries').textContent = stats.total_breweries.toLocaleString();
      document.getElementById('average-rating').textContent = stats.average_rating || 'N/A';
      document.getElementById('beer-styles').textContent = stats.beer_styles.toLocaleString();
      document.getElementById('venues').textContent = stats.venues.toLocaleString();
      document.getElementById('cities').textContent = stats.cities.toLocaleString();
      document.getElementById('countries').textContent = stats.countries.toLocaleString();
    } catch (error) {
      console.error('Error loading stats:', error);
    }
  }

  async loadTopBeers() {
    try {
      this.allBeers = await this.fetchData('top_beers');
      this.currentSortBy = 'rating';
      this.renderBeerList(this.allBeers);
      this.setupBeerSearch();
      this.setupBeerSort();
    } catch (error) {
      console.error('Error loading top beers:', error);
    }
  }

  async loadBeersWithSort(sortBy) {
    try {
      this.allBeers = await this.fetchData(`top_beers?sort=${sortBy}`);
      this.currentSortBy = sortBy;
      const searchTerm = document.getElementById('beer-search').value.toLowerCase();
      const filteredBeers = searchTerm ?
        this.allBeers.filter(beer =>
          beer.name.toLowerCase().includes(searchTerm) ||
          beer.brewery.toLowerCase().includes(searchTerm)
        ) : this.allBeers;
      this.renderBeerList(filteredBeers);
    } catch (error) {
      console.error('Error loading beers:', error);
    }
  }

  renderBeerList(beers) {
    const listContainer = document.getElementById('beer-list');
    listContainer.innerHTML = '';

    if (beers.length === 0) {
      listContainer.innerHTML = '<div class="list-group-item text-center text-muted">No beers found</div>';
      return;
    }

    beers.forEach((beer, index) => {
      const listItem = document.createElement('div');
      listItem.className = 'list-group-item beer-item';

      // show different info based on sort type
      let secondaryinfo = '';
      if (this.currentsortby === 'last_checkin' && beer.last_checkin) {
        const lastcheckindate = new date(beer.last_checkin).tolocaledatestring('en-us', {
          year: 'numeric',
          month: 'short',
          day: 'numeric'
        });
        secondaryinfo = `<small class="text-muted">last: ${lastcheckindate}</small>`;
      } else {
        secondaryinfo = `<small class="text-muted">⭐ ${parseFloat(beer.avg_rating).toFixed(1)} avg</small>`;
      }

      listItem.innerHTML = `
        <div class="d-flex justify-content-between align-items-start">
          <div class="flex-grow-1 me-3">
            <div class="d-flex align-items-center mb-1">
              <h6 class="beer-name mb-0"><a href="${beer.url}" target="_blank">${beer.name}</a></h6>
            </div>
            <p class="brewery-name mb-0">🏭 <a href="${beer.brewery_url}" target="_blank">${beer.brewery}</a></p>
          </div>
          <div class="d-flex flex-column align-items-end gap-1">
            <span class="badge rating-badge">
              ⭐ ${parseFloat(beer.avg_rating).toFixed(1)}
            </span>
            <span class="badge checkin-badge"
                  style="cursor: pointer;"
                  onclick="window.dashboard.showBeerVenues('${beer.name.replace(/'/g, "\\'")}', '${beer.brewery.replace(/'/g, "\\'")}', ${beer.beer_id}, ${beer.checkin_count})"
                  title="Click to see venues where you had this beer">
              ${beer.checkin_count}
            </span>
          </div>
        </div>
      `;
      listContainer.appendChild(listItem);
    });
  }

  setupBeerSort() {
    const sortSelect = document.getElementById('beer-sort-select');
    sortSelect.addEventListener('change', (e) => {
      this.loadBeersWithSort(e.target.value);
    });
  }

  setupBeerSearch() {
    const searchInput = document.getElementById('beer-search');
    searchInput.addEventListener('input', (e) => {
      const searchTerm = e.target.value.toLowerCase();
      const filteredBeers = this.allBeers.filter(beer =>
        beer.name.toLowerCase().includes(searchTerm) ||
        beer.brewery.toLowerCase().includes(searchTerm)
      );
      this.renderBeerList(filteredBeers);
    });
  }

  async loadCharts() {
    await Promise.all([
      this.createAbvChart(),
      this.createHourlyChart(),
      this.createDailyChart(),
      this.createRatingChart(),
      this.createStylesChart(),
      this.createBreweriesChart(),
      this.createCitiesChart(),
      this.createVenuesChart()
    ]);
  }

  async createAbvChart() {
    const data = await this.fetchData('abv_distribution');
    const ctx = document.getElementById('abv-chart').getContext('2d');

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.map(d => d.abv_range),
        datasets: [{
          label: 'Check-ins',
          data: data.map(d => d.count),
          backgroundColor: 'rgba(54, 162, 235, 0.8)',
          borderColor: 'rgba(54, 162, 235, 1)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { beginAtZero: true }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  async createHourlyChart() {
    const data = await this.fetchData('checkins_by_hour');
    const ctx = document.getElementById('hourly-chart').getContext('2d');

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.map(d => `${d.hour}:00`),
        datasets: [{
          label: 'Check-ins',
          data: data.map(d => d.count),
          backgroundColor: 'rgba(75, 192, 192, 0.8)',
          borderColor: 'rgba(75, 192, 192, 1)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { beginAtZero: true }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  async createDailyChart() {
    const data = await this.fetchData('checkins_by_day');
    const ctx = document.getElementById('daily-chart').getContext('2d');

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.map(d => d.day_name),
        datasets: [{
          label: 'Check-ins',
          data: data.map(d => d.count),
          backgroundColor: 'rgba(153, 102, 255, 0.8)',
          borderColor: 'rgba(153, 102, 255, 1)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { beginAtZero: true }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  async createRatingChart() {
    const data = await this.fetchData('rating_distribution');
    const ctx = document.getElementById('rating-chart').getContext('2d');

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.map(d => `${d.rating} ⭐`),
        datasets: [{
          label: 'Check-ins',
          data: data.map(d => d.count),
          backgroundColor: 'rgba(255, 206, 86, 0.8)',
          borderColor: 'rgba(255, 206, 86, 1)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { beginAtZero: true }
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  async createStylesChart() {
    const data = await this.fetchData('beer_styles');
    const ctx = document.getElementById('styles-chart').getContext('2d');

    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: data.map(d => d.style),
        datasets: [{
          data: data.map(d => d.count),
          backgroundColor: [
            '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
            '#9966FF', '#FF9F40', '#FF6384', '#C9CBCF',
            '#4BC0C0', '#FF6384'
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: { boxWidth: 12 }
          }
        }
      }
    });
  }

  async createBreweriesChart() {
    const data = await this.fetchData('top_breweries');
    const ctx = document.getElementById('breweries-chart').getContext('2d');

    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: data.map(d => d.name),
        datasets: [{
          data: data.map(d => d.checkin_count),
          backgroundColor: [
            '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
            '#9966FF', '#FF9F40', '#FF6384', '#C9CBCF',
            '#4BC0C0', '#FF6384'
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: { boxWidth: 12 }
          }
        }
      }
    });
  }

  async createCitiesChart() {
    const data = await this.fetchData('top_cities');
    const ctx = document.getElementById('cities-chart').getContext('2d');

    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: data.map(d => d.name),
        datasets: [{
          data: data.map(d => d.checkin_count),
          backgroundColor: [
            '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
            '#9966FF', '#FF9F40', '#FF6384', '#C9CBCF',
            '#4BC0C0', '#FF6384'
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: { boxWidth: 12 }
          }
        }
      }
    });
  }

  async createVenuesChart() {
    const data = await this.fetchData('top_venues');
    const ctx = document.getElementById('venues-chart').getContext('2d');

    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: data.map(d => d.name),
        datasets: [{
          data: data.map(d => d.checkin_count),
          backgroundColor: [
            '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0',
            '#9966FF', '#FF9F40', '#FF6384', '#C9CBCF',
            '#4BC0C0', '#FF6384'
          ]
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: { boxWidth: 12 }
          }
        }
      }
    });
  }
  async initMapBreweries() {
    try {
      const breweries = await this.fetchData('breweries_map');

      if (breweries.length === 0) {
        document.getElementById('map').innerHTML = '<div class="text-center p-5">No brewery location data available</div>';
        return;
      }

      // Calculate center point
      const centerLat = breweries.reduce((sum, v) => sum + v.lat, 0) / breweries.length;
      const centerLng = breweries.reduce((sum, v) => sum + v.lng, 0) / breweries.length;

      const map = L.map('mapbreweries',{wheelPxPerZoomLevel: 100}).setView([centerLat, centerLng], 6);

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors'
      }).addTo(map);

      breweries.forEach(brewery => {
        const marker = L.marker([brewery.lat, brewery.lng]).addTo(map);
        marker.bindPopup(`
          <strong><a href="${brewery.url}" target="_blank">${brewery.name}</a></strong><br>
          Check-ins: ${brewery.checkin_count}
        `);
      });

      // Fit map to show all markers
      const group = new L.featureGroup(breweries.map(v => L.marker([v.lat, v.lng])));
      map.fitBounds(group.getBounds().pad(0.1));
    } catch (error) {
      console.error('Error loading Breweries map:', error);
      document.getElementById('mapbreweries').innerHTML = '<div class="text-center p-5 text-danger">Error loading Breweries map data</div>';
    }
  }

  async initMapVenues() {
    try {
      const venues = await this.fetchData('venues_map');

      if (venues.length === 0) {
        document.getElementById('mapvenues').innerHTML = '<div class="text-center p-5">No venue location data available</div>';
        return;
      }

      // Calculate center point
      const centerLat = venues.reduce((sum, v) => sum + v.lat, 0) / venues.length;
      const centerLng = venues.reduce((sum, v) => sum + v.lng, 0) / venues.length;

      const map = L.map('mapvenues',{wheelPxPerZoomLevel: 100}).setView([centerLat, centerLng], 6);

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors'
      }).addTo(map);

      venues.forEach(venue => {
        const marker = L.marker([venue.lat, venue.lng]).addTo(map);
        marker.bindPopup(`
          <strong><a href="${venue.url}" target="_blank">${venue.name}</a></strong><br>
          Check-ins: ${venue.checkin_count}<br/>
          <button class="btn btn-primary btn-sm mt-2" onclick="window.dashboard.showVenueCheckins(${venue.id}, '${venue.name.replace(/'/g, "\\'")}')">
            View Check-ins
          </button>
        `);
      });

      // Fit map to show all markers
      const group = new L.featureGroup(venues.map(v => L.marker([v.lat, v.lng])));
      map.fitBounds(group.getBounds().pad(0.1));
    } catch (error) {
      console.error('Error loading venues map:', error);
      document.getElementById('mapvenues').innerHTML = '<div class="text-center p-5 text-danger">Error loading venues map data</div>';
    }
  }

  async showVenueCheckins(venueId, venueName) {
    try {
      // Update modal title
      document.getElementById('venue-modal-label').textContent = `📍 ${venueName}`;

      // Show loading state
      document.getElementById('venue-checkins-content').innerHTML = `
        <div class="text-center p-4">
          <div class="spinner-border" role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>
      `;

      // Show the modal using data attributes (works without Bootstrap JS object)
      const modalElement = document.getElementById('venue-modal');
      modalElement.style.display = 'block';
      modalElement.classList.add('show');
      modalElement.setAttribute('aria-modal', 'true');
      modalElement.setAttribute('role', 'dialog');

      // Add backdrop
      const backdrop = document.createElement('div');
      backdrop.className = 'modal-backdrop fade show';
      backdrop.id = 'venue-modal-backdrop';
      document.body.appendChild(backdrop);
      document.body.classList.add('modal-open');

      // Load checkins data
      const checkins = await this.fetchData(`venue_checkins/${venueId}`);
      this.renderVenueCheckins(checkins);
    } catch (error) {
      console.error('Error loading venue checkins:', error);
      document.getElementById('venue-checkins-content').innerHTML = '<div class="text-center text-danger p-4">Error loading check-ins</div>';
    }
  }

  closeVenueModal() {
    const modalElement = document.getElementById('venue-modal');
    const backdrop = document.getElementById('venue-modal-backdrop');

    modalElement.style.display = 'none';
    modalElement.classList.remove('show');
    modalElement.removeAttribute('aria-modal');
    modalElement.removeAttribute('role');

    if (backdrop) {
      backdrop.remove();
    }
    document.body.classList.remove('modal-open');
  }

  async showBeerVenues(beerName, breweryName, beerId, checkinCount) {
    try {
      // Update modal title
      document.getElementById('beer-venues-modal-label').textContent = `🍺 ${beerName} - ${breweryName}`;

      // Show loading state
      document.getElementById('beer-venues-content').innerHTML = `
        <div class="text-center p-4">
          <div class="spinner-border" role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>
      `;

      // Show the modal
      const modalElement = document.getElementById('beer-venues-modal');
      modalElement.style.display = 'block';
      modalElement.classList.add('show');
      modalElement.setAttribute('aria-modal', 'true');
      modalElement.setAttribute('role', 'dialog');

      // Add backdrop
      const backdrop = document.createElement('div');
      backdrop.className = 'modal-backdrop fade show';
      backdrop.id = 'beer-venues-modal-backdrop';
      document.body.appendChild(backdrop);
      document.body.classList.add('modal-open');

      // Load venues data
      const venues = await this.fetchData(`beer_checkins/${beerId}`)
      this.renderBeerVenues(venues, checkinCount);
    } catch (error) {
      console.error('Error loading beer venues:', error);
      document.getElementById('beer-venues-content').innerHTML = '<div class="text-center text-danger p-4">Error loading venues</div>';
    }
  }

  closeBeerVenuesModal() {
    const modalElement = document.getElementById('beer-venues-modal');
    const backdrop = document.getElementById('beer-venues-modal-backdrop');

    modalElement.style.display = 'none';
    modalElement.classList.remove('show');
    modalElement.removeAttribute('aria-modal');
    modalElement.removeAttribute('role');

    if (backdrop) {
      backdrop.remove();
    }
    document.body.classList.remove('modal-open');
  }

  renderBeerVenues(venues, totalCheckins) {
    const container = document.getElementById('beer-venues-content');

    if (venues.length === 0) {
      container.innerHTML = '<div class="text-center text-muted p-4">No venues found for this beer</div>';
      return;
    }

    const venuesHtml = venues.map(venue => {
      const lastCheckin = new Date(venue.last_checkin).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
      });

      const avgRating = venue.avg_rating ?
        `<span class="badge venue-rating">${parseFloat(venue.avg_rating).toFixed(1)} ⭐</span>` :
        '<span class="badge bg-secondary">No rating</span>';

      let locationText = '';
      if (venue.location_json) {
        try {
          const location = JSON.parse(venue.location_json);
          locationText = `<small class="text-muted">📍 ${location.city || 'Unknown'}, ${location.country || 'Unknown'}</small>`;
        } catch (e) {
          locationText = '';
        }
      }

      return `
        <div class="venue-item" onclick="window.dashboard.showVenueCheckins(${venue.id}, '${venue.venue_name.replace(/'/g, "\\'")}')">
          <div class="d-flex justify-content-between align-items-start mb-2">
            <div class="flex-grow-1">
              <h6 class="mb-1">${venue.venue_name}</h6>
              ${locationText}
            </div>
            <div class="text-end">
              ${avgRating}
              <div class="mt-1">
                <span class="badge venue-checkin-count">${venue.checkin_count} check-ins</span>
              </div>
            </div>
          </div>
          <small class="text-muted">Last visit: ${lastCheckin}</small>
        </div>
      `;
    }).join('');

    container.innerHTML = `
      <div class="mb-3">
        <h6>Total Check-ins: ${totalCheckins} • Venues: ${venues.length}</h6>
        <p class="text-muted small mb-3">Click on any venue to see all check-ins there</p>
      </div>
      ${venuesHtml}
    `;
  }

  renderVenueCheckins(checkins) {
    const container = document.getElementById('venue-checkins-content');

    if (checkins.length === 0) {
      container.innerHTML = '<div class="text-center text-muted p-4">No check-ins found for this venue</div>';
      return;
    }

    console.log(checkins);

    const checkinsHtml = checkins.map(checkin => {
      const date = new Date(checkin.created_at).toLocaleDateString('en-UK', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });

      const rating = checkin.rating_score ?
        `<span class="badge checkin-rating">${checkin.rating_score} ⭐️</span>` :
        '<span class="badge bg-secondary">No rating</span>';

      const comment = checkin.comment ?
        `<p class="mb-2 mt-2"><em>"${checkin.comment}"</em></p>` : '';

      return `
        <div class="checkin-item">
          <div class="d-flex justify-content-between align-items-start mb-2">
            <div class="flex-grow-1">
              <h6 class="mb-1"><a href="${checkin.beer_url}" target="_blank">🍺 ${checkin.beer_name}</a></h6>
              <small class="text-muted"><a href="${checkin.brewery_url}" target="_blank">🏭 ${checkin.brewery_name}</a></small>
            </div>
            <div class="text-end">
              ${rating}
              <div class="checkin-date mt-1">${date}</div>
            </div>
          </div>
          ${comment}
        </div>
      `;
    }).join('');

    container.innerHTML = `
      <div class="mb-3">
        <h6>Total Check-ins: ${checkins.length}</h6>
      </div>
      ${checkinsHtml}
    `;
  }
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
  new BeerDashboard();
});
